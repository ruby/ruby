# frozen_string_literal: false
require 'socket'
require 'openssl'

module TestNetHTTPUtils

  class Forbidden < StandardError; end

  class HTTPServer
    def initialize(config, &block)
      @config = config
      @server = TCPServer.new(@config['host'], 0)
      @port = @server.addr[1]
      @procs = {}

      if @config['ssl_enable']
        context = OpenSSL::SSL::SSLContext.new
        context.cert = @config['ssl_certificate']
        context.key = @config['ssl_private_key']
        context.tmp_dh_callback = @config['ssl_tmp_dh_callback']
        @ssl_server = OpenSSL::SSL::SSLServer.new(@server, context)
      end

      @block = block
    end

    def start
      @thread = Thread.new do
        loop do
          socket = @ssl_server ? @ssl_server.accept : @server.accept
          run(socket)
        rescue => e
          puts "Error: #{e.class} - #{e.message}"
        ensure
          socket.close if socket
        end
      end
    end

    def run(socket)
      handle_request(socket)
    end

    def shutdown
      @thread.kill if @thread
      @server.close if @server
    end

    def mount(path, proc)
      @procs[path] = proc
    end

    def mount_proc(path, &block)
      mount(path, block.to_proc)
    end

    def handle_request(socket)
      request_line = socket.gets
      return if request_line.nil? || request_line.strip.empty?

      method, path, version = request_line.split
      headers = {}
      while (line = socket.gets)
        break if line.strip.empty?
        key, value = line.split(': ', 2)
        headers[key] = value.strip
      end

      if headers['Expect'] == '100-continue'
        socket.write "HTTP/1.1 100 Continue\r\n\r\n"
      end

      req = Request.new(method, path, headers, socket)
      if @procs.key?(req.path) || @procs.key?("#{req.path}/")
        proc = @procs[req.path] || @procs["#{req.path}/"]
        res = Response.new(socket)
        begin
          proc.call(req, res)
        rescue Forbidden
          res.status = 403
        end
        res.finish
      else
        @block.call(method, path, headers, socket)
      end
    end

    def port
      @port
    end

    class Request
      attr_reader :method, :path, :headers, :query, :body
      def initialize(method, path, headers, socket)
        @method = method
        @path, @query = parse_path_and_query(path)
        @headers = headers
        @socket = socket
        if method == 'POST' && (@path == '/continue' || @headers['Content-Type'].include?('multipart/form-data'))
          if @headers['Transfer-Encoding'] == 'chunked'
            @body = read_chunked_body
          else
            @body = read_body
          end
          @query = @body.split('&').each_with_object({}) do |pair, hash|
            key, value = pair.split('=')
            hash[key] = value
          end if @body && @body.include?('=')
        end
      end

      def [](key)
        @headers[key.downcase]
      end

      def []=(key, value)
        @headers[key.downcase] = value
      end

      def continue
        @socket.write "HTTP\/1.1 100 continue\r\n\r\n"
      end

      def query
        @query
      end

      def remote_ip
        @socket.peeraddr[3]
      end

      def peeraddr
        @socket.peeraddr
      end

      private

      def parse_path_and_query(path)
        path, query_string = path.split('?', 2)
        query = {}
        if query_string
          query_string.split('&').each do |pair|
            key, value = pair.split('=', 2)
            query[key] = value
          end
        end
        [path, query]
      end

      def read_body
        content_length = @headers['Content-Length']&.to_i
        return unless content_length && content_length > 0
        @socket.read(content_length)
      end

      def read_chunked_body
        body = ""
        while (chunk_size = @socket.gets.strip.to_i(16)) > 0
          body << @socket.read(chunk_size)
          @socket.read(2) # read \r\n after each chunk
        end
        body
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
        when 403 then 'Forbidden'
        else 'Unknown'
        end
      end
    end
  end

  def start(&block)
    new().start(&block)
  end

  def new
    klass = Net::HTTP::Proxy(config('proxy_host'), config('proxy_port'))
    http = klass.new(config('host'), config('port'))
    http.set_debug_output logfile()
    http
  end

  def config(key)
    @config ||= self.class::CONFIG
    @config[key]
  end

  def logfile
    $DEBUG ? $stderr : NullWriter.new
  end

  def setup
    spawn_server
  end

  def teardown
    if @server
      @server.shutdown
    end
    @log_tester.call(@log) if @log_tester
    Net::HTTP.version_1_2
  end

  def spawn_server
    @log = []
    @log_tester = lambda {|log| assert_equal([], log) }
    @config = self.class::CONFIG
    @server = HTTPServer.new(@config) do |method, path, headers, socket|
      case method
      when 'HEAD'
        handle_head(path, headers, socket)
      when 'GET'
        handle_get(path, headers, socket)
      when 'POST'
        handle_post(path, headers, socket)
      when 'PATCH'
        handle_patch(path, headers, socket)
      else
        socket.print "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n"
      end
      @log << "DEBUG accept: #{@config['host']}:#{socket.addr[1]}" if @logger_level == :debug
    end
    @server.start
    @config['port'] = @server.port
  end

  def handle_head(path, headers, socket)
    if headers['Accept'] != '*/*'
      content_type = headers['Accept']
    else
      content_type = $test_net_http_data_type
    end
    response = "HTTP/1.1 200 OK\r\nContent-Type: #{content_type}\r\nContent-Length: #{$test_net_http_data.bytesize}"
    socket.print(response)
  end

  def handle_get(path, headers, socket)
    if headers['Accept'] != '*/*'
      content_type = headers['Accept']
    else
      content_type = $test_net_http_data_type
    end
    response = "HTTP/1.1 200 OK\r\nContent-Type: #{content_type}\r\nContent-Length: #{$test_net_http_data.bytesize}\r\n\r\n#{$test_net_http_data}"
    socket.print(response)
  end

  def handle_post(path, headers, socket)
    body = socket.read(headers['Content-Length'].to_i)
    scheme = headers['X-Request-Scheme'] || 'http'
    host = @config['host']
    port = socket.addr[1]
    charset = parse_content_type(headers['Content-Type'])[1]
    path = "#{scheme}://#{host}:#{port}#{path}"
    path = path.encode(charset) if charset
    response = "HTTP/1.1 200 OK\r\nContent-Type: #{headers['Content-Type']}\r\nContent-Length: #{body.bytesize}\r\nX-request-uri: #{path}\r\n\r\n#{body}"
    socket.print(response)
  end

  def handle_patch(path, headers, socket)
    body = socket.read(headers['Content-Length'].to_i)
    response = "HTTP/1.1 200 OK\r\nContent-Type: #{headers['Content-Type']}\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    socket.print(response)
  end

  def parse_content_type(content_type)
    return [nil, nil] unless content_type
    type, *params = content_type.split(';').map(&:strip)
    charset = params.find { |param| param.start_with?('charset=') }
    charset = charset.split('=', 2).last if charset
    [type, charset]
  end

  $test_net_http = nil
  $test_net_http_data = (0...256).to_a.map { |i| i.chr }.join('') * 64
  $test_net_http_data.force_encoding("ASCII-8BIT")
  $test_net_http_data_type = 'application/octet-stream'

  class NullWriter
    def <<(_s); end

    def puts(*_args); end

    def print(*_args); end

    def printf(*_args); end
  end

  def self.clean_http_proxy_env
    orig = {
      'http_proxy' => ENV['http_proxy'],
      'http_proxy_user' => ENV['http_proxy_user'],
      'http_proxy_pass' => ENV['http_proxy_pass'],
      'no_proxy' => ENV['no_proxy'],
    }

    orig.each_key do |key|
      ENV.delete key
    end

    yield
  ensure
    orig.each do |key, value|
      ENV[key] = value
    end
  end
end
