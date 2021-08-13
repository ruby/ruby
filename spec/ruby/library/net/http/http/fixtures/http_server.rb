require 'socket'

module NetHTTPSpecs
  class NullWriter
    def <<(s) end
    def puts(*args) end
    def print(*args) end
    def printf(*args) end
  end

  class SmallHTTPServer
    def initialize(bind_address)
      @server = TCPServer.new(bind_address, 0)
      @running = Mutex.new
      @thread = Thread.new {
        Thread.current.abort_on_exception = true
        listen
      }
    end

    def port
      @server.addr[1]
    end

    def listen
      loop do
        begin
          client = @server.accept
        rescue IOError => e
          if @running.locked? # close
            break
          else
            raise e
          end
        end

        handle_client(client)
      end
    end

    def handle_client(client)
      begin
        until client.closed?
          request = client.gets("\r\n\r\n")
          break unless request
          handle_request(client, request)
        end
      ensure
        client.close
      end
    end

    def parse_request(request)
      request, *headers = request.chomp.lines.map { |line| line.chomp }
      request_method, request_uri, _http_version = request.split
      headers = headers.map { |line| line.split(': ', 2) }.to_h
      [request_method, request_uri, headers]
    end

    def handle_request(client, request)
      request_method, request_uri, headers = parse_request(request)

      if headers.include? 'Content-Length'
        request_body_size = Integer(headers['Content-Length'])
        request_body = client.read(request_body_size)
      end

      case request_uri
      when '/'
        raise request_method unless request_method == 'GET'
        reply(client, "This is the index page.", request_method)
      when '/request'
        reply(client, "Request type: #{request_method}", request_method)
      when '/request/body'
        reply(client, request_body, request_method)
      when '/request/header'
        reply(client, headers.inspect, request_method)
      when '/request/basic_auth'
        reply(client, "username: \npassword: ", request_method)
      else
        raise request_uri
      end
    end

    def reply(client, body, request_method)
      client.print "HTTP/1.1 200 OK\r\n"
      if request_method == 'HEAD'
        client.close
      else
        client.print "Content-Type: text/plain\r\n"
        client.print "Content-Length: #{body.bytesize}\r\n"
        client.print "\r\n"
        client.print body
      end
    end

    def close
      @running.lock
      @server.close
      @thread.join
    end
  end

  @server = nil

  class << self
    def port
      raise "server not started" unless @server
      @server.port
    end

    def start_server
      bind_address = platform_is(:windows) ? "localhost" : "127.0.0.1"
      @server = SmallHTTPServer.new(bind_address)
    end

    def stop_server
      if @server
        @server.close
        @server = nil
      end
    end
  end
end
