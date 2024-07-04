require 'socket'
require 'base64'

class SimpleHTTPServer
  def initialize(bind_addr, port, log)
    @server = TCPServer.new(bind_addr, port)
    @log = log
    @procs = {}
  end

  def mount_proc(path, proc)
    @procs[path] = proc
  end

  def start
    @thread = Thread.new do
      loop do
        client = @server.accept
        handle_request(client)
        client.close
      end
    end
  end

  def shutdown
    @thread.kill
    @server.close
  end

  private

  def handle_request(client)
    request_line = client.gets
    return if request_line.nil?

    method, path, _ = request_line.split
    headers = {}
    while (line = client.gets) && line != "\r\n"
      key, value = line.split(": ", 2)
      headers[key.downcase] = value.strip
    end

    if @procs.key?(path) || @procs.key?("#{path}/")
      proc = @procs[path] || @procs["#{path}/"]
      req = Request.new(method, path, headers)
      res = Response.new(client)
      proc.call(req, res)
      res.finish
    else
      @log << "ERROR `#{path}' not found"
      client.print "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
    end
  rescue ::TestOpenURI::Unauthorized => e
    @log << "ERROR Unauthorized"
    client.print "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n"
  end

  class Request
    attr_reader :method, :path, :headers
    def initialize(method, path, headers)
      @method = method
      @path = path
      @headers = headers
      parse_basic_auth
    end

    def [](key)
      @headers[key.downcase]
    end

    def []=(key, value)
      @headers[key.downcase] = value
    end

    private

    def parse_basic_auth
      auth = @headers['Authorization']
      return unless auth && auth.start_with?('Basic ')

      encoded_credentials = auth.split(' ', 2).last
      decoded_credentials = Base64.decode64(encoded_credentials)
      @username, @password = decoded_credentials.split(':', 2)
    end
  end

  class Response
    attr_accessor :body, :headers, :status, :chunked, :cookies
    def initialize(client)
      @client = client
      @body = ""
      @headers = {}
      @status = 200
      @chunked = false
      @cookies = []
    end

    def [](key)
      @headers[key.downcase]
    end

    def []=(key, value)
      @headers[key.downcase] = value
    end

    def write_chunk(chunk)
      return unless @chunked
      @client.write("#{chunk.bytesize.to_s(16)}\r\n")
      @client.write("#{chunk}\r\n")
    end

    def finish
      @client.write build_response_headers
      if @chunked
        write_chunk(@body)
        @client.write "0\r\n\r\n"
      else
        @client.write @body
      end
    end

    private

    def build_response_headers
      response = "HTTP/1.1 #{@status} #{status_message(@status)}\r\n"
      if @chunked
        @headers['Transfer-Encoding'] = 'chunked'
      else
        @headers['Content-Length'] = @body.bytesize.to_s
      end
      @headers.each do |key, value|
        response << "#{key}: #{value}\r\n"
      end
      @cookies.each do |cookie|
        response << "Set-Cookie: #{cookie}\r\n"
      end
      response << "\r\n"
      response
    end

    def status_message(code)
      case code
      when 200 then 'OK'
      when 301 then 'Moved Permanently'
      else 'Unknown'
      end
    end
  end
end

module TestOpenURIUtils
  class Unauthorized < StandardError; end

  def with_http(log_tester=lambda {|log| assert_equal([], log) })
    log = []
    srv = SimpleHTTPServer.new('localhost', 0, log)

    server_thread = srv.start
    server_thread2 = Thread.new {
      server_thread.join
      if log_tester
        log_tester.call(log)
      end
    }

    port = srv.instance_variable_get(:@server).addr[1]

    client_thread = Thread.new {
      begin
        yield srv, "http://localhost:#{port}", server_thread, log
      ensure
        srv.shutdown
      end
    }
    assert_join_threads([client_thread, server_thread2])
  end
end