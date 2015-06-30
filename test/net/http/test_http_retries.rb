# coding: US-ASCII
require 'test/unit'
require 'net/http'
require 'stringio'
require 'socket'

class TestNetHTTPIdempotentRetries < Test::Unit::TestCase

  class SimpleHttpServer

    def initialize
      @address = '127.0.0.1'
      @port = 3000
      @handlers = []
    end

    attr_reader :address, :port

    # The given proc should accept the follow block arguments:
    #
    # * `http_method` - String
    # * `request_uri` - String
    # * `request_headers` - Hash<String,String>
    # * `socket` - Socket
    #
    # The block is expected to read the request body and to write
    # the full response.
    def handle(&handler)
      @handlers << Proc.new
    end

    def start
      @server = TCPServer.new(@address, @port)
      @thread = Thread.new do
        loop do
          begin
            socket = @server.accept
            method, uri, _ = socket.gets.split(/\s+/)
            @handlers.shift.call(method, uri, headers(socket), socket)
            socket.close unless socket.closed?
          rescue
            @server.close
            @server = TCPServer.new(@address, @port)
            retry
          end
        end
      end
    end

    def stop
      @thread.kill
      @server.close
    end

    private

    def headers(socket)
      headers = {}
      line = socket.gets
      until line == "\r\n"
        key, value = line.split(/:\s*/, 2)
        headers[key.downcase] = value
        line = socket.gets
      end
      headers
    end

  end

  def setup
    @server = SimpleHttpServer.new
  end

  def teardown
    @server.stop
  end

  def test_idempotent_retry_default
    @server.handle do |_, _, headers, socket|
      socket.close # close without responding
    end
    @server.handle do |_, _, headers, socket|
      socket.print("HTTP/1.1 200 OK\r\n")
      socket.print("\r\n")
    end
    @server.start

    req = Net::HTTP::Get.new('/')
    http = Net::HTTP.new(@server.address, @server.port)
    res = http.request(req)

    assert_equal('200', res.code)
  end

  def test_retry_can_be_disabled
    @server.handle do |_, _, headers, socket|
      socket.close # close without responding
    end
    @server.handle do |_, _, headers, socket|
      socket.print("HTTP/1.1 200 OK\r\n")
      socket.print("\r\n")
    end
    @server.start

    req = Net::HTTP::Get.new('/')
    req.retry_networking_errors = false

    http = Net::HTTP.new(@server.address, @server.port)
    assert_raises {
      http.request(req)
    }
  end

  def test_idempotent_retry_rewinds_put_body_stream
    @server.handle do |_, _, headers, socket|
      # intentionally read some of the data, not all
      socket.read(headers['content-length'].to_i / 2)
      socket.close
    end
    @server.handle do |_, _, headers, socket|
      body = socket.read(headers['content-length'].to_i)
      socket.print("HTTP/1.1 200 OK\r\n")
      socket.print("Content-Length: #{body.size}\n")
      socket.print("\r\n")
      socket.print(body)
    end
    @server.start

    body = StringIO.new('io-body')
    req = Net::HTTP::Put.new('/', 'Content-Length' => body.size.to_s )
    req.body_stream = body

    http = Net::HTTP.new(@server.address, @server.port)
    http.read_timeout = 0.5

    assert_nothing_raised {
      http.request(req)
    }
  end

  def test_idempotent_retry_disabled_with_request_block
    one_meg = 1024 * 1024
    @server.handle do |_, _, headers, socket|
      socket.print("HTTP/1.1 200 OK\r\n")
      socket.print("Content-Length: #{one_meg}\n")
      socket.print("\r\n")
      socket.print('.' * (one_meg / 2))
      raise 'error' # forcefully close the connection
    end
    @server.handle do |_, _, headers, socket|
      socket.print("HTTP/1.1 200 OK\r\n")
      socket.print("Content-Length: #{one_meg}\n")
      socket.print("\r\n")
      socket.print('.' * one_meg)
    end
    @server.start

    http = Net::HTTP.new(@server.address, @server.port)
    http.read_timeout = 0.5

    yield_count = 0
    byte_count = 0

    assert_raises {
      http.request(Net::HTTP::Get.new('/')) do |resp|
        yield_count += 1
        resp.read_body do |bytes|
          byte_count += bytes.bytesize
        end
      end
    }
    assert_equal(one_meg / 2, byte_count)
    assert_equal(1, yield_count)
  end
end
