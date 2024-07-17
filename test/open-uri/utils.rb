require 'socket'
require 'net/http'
begin
  require 'openssl'
rescue LoadError
end

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
  rescue ::TestOpenURI::Unauthorized
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
      decoded_credentials = [encoded_credentials].pack("m")
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

class SimpleHTTPProxyServer
  def initialize(host, port, auth_proc = nil, log, access_log)
    @server = TCPServer.new(host, port)
    @auth_proc = auth_proc
    @log = log
    @access_log = access_log
  end

  def start
    @thread = Thread.new do
      loop do
        client = @server.accept
        request_line = client.gets
        headers = {}
        while (line = client.gets) && (line != "\r\n")
          key, value = line.chomp.split(/:\s*/, 2)
          headers[key] = value
        end
        next unless request_line

        method, path, _ = request_line.split(' ')
        handle_request(client, method, path, request_line, headers)
      rescue IOError
      end
    end
  end

  def shutdown
    @thread.kill
    @server.close
  end

  private

  def handle_request(client, method, path, request_line, headers)
    if @auth_proc
      req = Request.new(method, path, request_line, headers)
      res = Struct.new(:body, :status).new("", 200)
      @auth_proc.call(req, res)
      if res.status != 200
        client.print "HTTP/1.1 #{res.status}\r\nContent-Type: text/plain\r\n\r\n#{res.body}"
        return
      end
    end

    if method == 'CONNECT'
      proxy_connect(path, client)
    else
      proxy_request(path, client)
    end
  rescue TestOpenURIProxy::ProxyAuthenticationRequired
    @log << "ERROR ProxyAuthenticationRequired"
    client.print "HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\n\r\n"
  ensure
    client.close
  end

  def proxy_connect(path, client)
    host, port = path.split(':')
    backend = TCPSocket.new(host, port.to_i)
    client.puts "HTTP/1.1 200 Connection Established\r\n\r\n"
    @access_log << "CONNECT #{path} \n"
    begin
      while fds = IO.select([client, backend])
        if fds[0].include?(client)
          data = client.readpartial(1024)
          backend.write(data)
        elsif fds[0].include?(backend)
          data = backend.readpartial(1024)
          client.write(data)
        end
      end
    rescue
      backend.close
    end
  end

  def proxy_request(path, client)
    path.gsub!(/\Ahttps?:\/\//, '')
    host, path = path.split('/')
    host, port = host.split(':')
    Net::HTTP.start(host, port) do |http|
      response = http.get("/#{path}")
      client.print "HTTP/1.1 #{response.code}\r\nContent-Type: #{response.content_type}\r\n\r\n#{response.body}"
    end
  end

  class Request
    attr_reader :method, :path, :request_line, :headers
    def initialize(method, path, request_line, headers)
      @method = method
      @path = path
      @request_line = request_line
      @headers = headers
    end

    def [](key)
      @headers[key]
    end
  end
end

class SimpleHTTPSServer
  def initialize(cert, key, dh, bind_addr, port, log)
    @cert = cert
    @key = key
    @dh = dh
    @bind_addr = bind_addr
    @port = port
    @log = log
    @server = TCPServer.new(@bind_addr, @port)
    context = OpenSSL::SSL::SSLContext.new
    context.cert = @cert
    context.key = @key
    context.tmp_dh_callback = proc { @dh }
    @ssl_server = OpenSSL::SSL::SSLServer.new(@server, context)
  end

  def start
    @thread = Thread.new do
      loop do
        ssl_socket = @ssl_server.accept
        handle_request(ssl_socket)
        ssl_socket.close
      end
    rescue OpenSSL::SSL::SSLError
    end
  end

  def shutdown
    @thread.kill
    @server.close
  end

  def handle_request(socket)
    request_line = socket.gets
    return if request_line.nil? || request_line.strip.empty?

    _, path, _ = request_line.split
    headers = {}
    while (line = socket.gets)
      break if line.strip.empty?
      key, value = line.split(': ', 2)
      headers[key] = value.strip
    end

    response = case path
               when '/data'
                 "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 3\r\n\r\nddd"
               when "/proxy"
                 "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nproxy"
               else
                 "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
               end

    socket.print(response)
  end
end

module TestOpenURIUtils
  class Unauthorized < StandardError; end
  class ProxyAuthenticationRequired < StandardError; end

  def with_http(log_tester=lambda {|log| assert_equal([], log) })
    log = []
    host = "127.0.0.1"
    srv = SimpleHTTPServer.new(host, 0, log)

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
        yield srv, "http://#{host}:#{port}", server_thread, log
      ensure
        srv.shutdown
      end
    }
    assert_join_threads([client_thread, server_thread2])
  end

  def with_https_proxy(proxy_log_tester=lambda {|proxy_log, proxy_access_log| assert_equal([], proxy_log) })
    proxy_log = []
    proxy_access_log = []
    with_https {|srv, dr, url|
      srv.instance_variable_get(:@server).setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
      cacert_filename = "#{dr}/cacert.pem"
      open(cacert_filename, "w") {|f| f << CA_CERT }
      cacert_directory = "#{dr}/certs"
      Dir.mkdir cacert_directory
      hashed_name = "%08x.0" % OpenSSL::X509::Certificate.new(CA_CERT).subject.hash
      open("#{cacert_directory}/#{hashed_name}", "w") {|f| f << CA_CERT }
      proxy_host = '127.0.0.1'
      proxy = SimpleHTTPProxyServer.new(proxy_host, 0, proxy_log, proxy_access_log)
      proxy_port = proxy.instance_variable_get(:@server).addr[1]
      proxy_thread = proxy.start
      thread = Thread.new {
        proxy_thread.join
        if proxy_log_tester
          proxy_log_tester.call(proxy_log, proxy_access_log)
        end
      }
      begin
        yield srv, dr, url, cacert_filename, cacert_directory, proxy_host, proxy_port
        sleep 1
      ensure
        proxy.shutdown
      end
      assert_join_threads([thread])
    }
  end

  if defined?(OpenSSL::SSL)
  def with_https(log_tester=lambda {|log| assert_equal([], log) })
    log = []
    Dir.mktmpdir {|dr|
      cert = OpenSSL::X509::Certificate.new(SERVER_CERT)
      key = OpenSSL::PKey::RSA.new(SERVER_KEY)
      dh = OpenSSL::PKey::DH.new(DHPARAMS)
      host = '127.0.0.1'
      srv = SimpleHTTPSServer.new(cert, key, dh, host, 0, log)
      port = srv.instance_variable_get(:@server).addr[1]
      threads = []
      server_thread = srv.start
      threads << Thread.new {
        server_thread.join
        if log_tester
          log_tester.call(log)
        end
      }
      threads << Thread.new {
        begin
          yield srv, dr, "https://#{host}:#{port}"
        ensure
          srv.shutdown
        end
      }
      assert_join_threads(threads)
    }
  end

  # cp /etc/ssl/openssl.cnf . # I copied from OpenSSL 1.1.1b source

  # mkdir demoCA demoCA/private demoCA/newcerts
  # touch demoCA/index.txt
  # echo 00 > demoCA/serial
  # openssl genrsa -des3 -out demoCA/private/cakey.pem 2048
  # openssl req -new -key demoCA/private/cakey.pem -out demoCA/careq.pem -subj "/C=JP/ST=Tokyo/O=RubyTest/CN=Ruby Test CA"
  # # basicConstraints=CA:TRUE is required; the default openssl.cnf has it in [v3_ca]
  # openssl ca -config openssl.cnf -extensions v3_ca -out demoCA/cacert.pem -startdate 090101000000Z -enddate 491231235959Z -batch -keyfile demoCA/private/cakey.pem -selfsign -infiles demoCA/careq.pem

  # mkdir server
  # openssl genrsa -des3 -out server/server.key 2048
  # openssl req -new -key server/server.key -out server/csr.pem -subj "/C=JP/ST=Tokyo/O=RubyTest/CN=127.0.0.1"
  # openssl ca -config openssl.cnf -startdate 090101000000Z -enddate 491231235959Z -in server/csr.pem -keyfile demoCA/private/cakey.pem -cert demoCA/cacert.pem -out server/cert.pem

  # demoCA/cacert.pem => TestOpenURISSL::CA_CERT
  # server/cert.pem => TestOpenURISSL::SERVER_CERT
  # `openssl rsa -in server/server.key -text` => TestOpenURISSL::SERVER_KEY

  CA_CERT = <<'End'
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 0 (0x0)
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=JP, ST=Tokyo, O=RubyTest, CN=Ruby Test CA
        Validity
            Not Before: Jan  1 00:00:00 2009 GMT
            Not After : Dec 31 23:59:59 2049 GMT
        Subject: C=JP, ST=Tokyo, O=RubyTest, CN=Ruby Test CA
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                RSA Public-Key: (2048 bit)
                Modulus:
                    00:ad:f3:4d:5b:0b:01:54:cc:86:36:d1:93:6b:33:
                    56:25:90:61:d6:9a:a0:f4:24:20:ee:c8:14:ab:0f:
                    4b:89:d8:7c:bb:c0:f8:7f:fb:e9:a2:d5:1c:6b:6f:
                    dc:5c:23:b1:49:aa:2c:e8:ca:43:48:64:69:4b:8a:
                    bd:44:57:9b:14:d9:7a:b2:49:00:d6:c2:74:67:62:
                    52:1d:a9:32:df:fe:7a:22:20:49:83:e1:cb:3d:dc:
                    1a:2a:f0:36:20:c1:e8:c8:89:d4:51:1a:68:91:20:
                    e0:ba:67:0a:b2:6b:f8:e3:8c:f5:ee:a1:36:b1:89:
                    ec:23:b6:f2:39:a9:b9:2e:ea:de:d9:86:e5:42:11:
                    46:ed:10:9a:90:76:44:4e:4d:49:2d:49:e8:e3:cb:
                    ff:7a:7d:80:cb:bf:c4:c3:69:ba:9c:60:4a:de:af:
                    bf:26:78:b8:fb:46:d1:37:d0:89:ba:78:93:6a:37:
                    a5:e9:58:e7:e2:e3:7d:7c:95:20:79:41:56:15:cd:
                    b2:c6:3b:e1:b7:e7:ba:47:60:9a:05:b1:07:f3:26:
                    72:9d:3b:1b:02:18:3d:d5:de:e6:e9:30:a9:b5:8f:
                    15:1b:40:f9:64:61:54:d3:53:e8:c4:29:4a:89:f3:
                    e5:0d:fd:16:61:ee:f2:6d:8a:45:a8:34:7e:53:46:
                    8e:87
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Subject Key Identifier:
                A0:7E:0B:AD:A3:AD:37:D7:21:0B:75:6F:8A:90:5F:8C:C9:69:DF:98
            X509v3 Authority Key Identifier:
                keyid:A0:7E:0B:AD:A3:AD:37:D7:21:0B:75:6F:8A:90:5F:8C:C9:69:DF:98

            X509v3 Basic Constraints: critical
                CA:TRUE
    Signature Algorithm: sha256WithRSAEncryption
         06:ea:06:02:19:9a:cb:94:a2:7e:c0:86:71:66:e7:a5:71:46:
         a2:25:55:f5:e5:58:df:d1:91:58:e6:8a:0e:91:b3:22:4c:88:
         4d:5f:02:af:0f:73:65:0d:af:9a:f2:e4:36:f3:1f:e8:28:1d:
         9c:74:72:5b:f7:12:e8:fa:45:d6:df:e5:f1:d3:91:f4:0e:db:
         e2:56:63:ee:82:57:6f:12:ad:d7:0d:de:5a:8c:3d:76:d2:87:
         c9:48:1c:c4:f3:89:63:3c:c2:25:e0:dd:63:a6:4c:6c:5a:07:
         7b:86:78:62:86:02:a1:ef:0e:41:75:c5:d4:61:ab:c3:3b:9b:
         51:0b:e6:34:6d:0b:14:5a:2d:aa:d3:58:26:43:8f:4c:d7:45:
         73:1e:67:66:5e:f3:0c:69:70:27:a1:d5:70:f3:5a:10:98:c8:
         4f:8a:3b:9f:ad:8e:8d:49:8f:fb:f6:36:5d:4f:70:f9:4f:54:
         33:cf:a2:a6:1d:8c:61:b9:30:42:f2:49:d1:3d:a1:f1:eb:1e:
         78:a6:30:f8:8a:48:89:c7:3e:bd:0d:d8:72:04:a6:00:e5:62:
         a4:13:3f:9e:b6:86:25:dc:d1:ff:3a:fc:f5:0e:e4:0e:f7:b8:
         66:90:fe:4f:c2:54:2a:7f:61:6e:e7:4b:bf:40:7e:75:30:02:
         5b:bb:91:1b
-----BEGIN CERTIFICATE-----
MIIDXDCCAkSgAwIBAgIBADANBgkqhkiG9w0BAQsFADBHMQswCQYDVQQGEwJKUDEO
MAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRUwEwYDVQQDDAxSdWJ5
IFRlc3QgQ0EwHhcNMDkwMTAxMDAwMDAwWhcNNDkxMjMxMjM1OTU5WjBHMQswCQYD
VQQGEwJKUDEOMAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRUwEwYD
VQQDDAxSdWJ5IFRlc3QgQ0EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
AQCt801bCwFUzIY20ZNrM1YlkGHWmqD0JCDuyBSrD0uJ2Hy7wPh/++mi1Rxrb9xc
I7FJqizoykNIZGlLir1EV5sU2XqySQDWwnRnYlIdqTLf/noiIEmD4cs93Boq8DYg
wejIidRRGmiRIOC6Zwqya/jjjPXuoTaxiewjtvI5qbku6t7ZhuVCEUbtEJqQdkRO
TUktSejjy/96fYDLv8TDabqcYErer78meLj7RtE30Im6eJNqN6XpWOfi4318lSB5
QVYVzbLGO+G357pHYJoFsQfzJnKdOxsCGD3V3ubpMKm1jxUbQPlkYVTTU+jEKUqJ
8+UN/RZh7vJtikWoNH5TRo6HAgMBAAGjUzBRMB0GA1UdDgQWBBSgfguto6031yEL
dW+KkF+MyWnfmDAfBgNVHSMEGDAWgBSgfguto6031yELdW+KkF+MyWnfmDAPBgNV
HRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAG6gYCGZrLlKJ+wIZxZuel
cUaiJVX15Vjf0ZFY5ooOkbMiTIhNXwKvD3NlDa+a8uQ28x/oKB2cdHJb9xLo+kXW
3+Xx05H0DtviVmPugldvEq3XDd5ajD120ofJSBzE84ljPMIl4N1jpkxsWgd7hnhi
hgKh7w5BdcXUYavDO5tRC+Y0bQsUWi2q01gmQ49M10VzHmdmXvMMaXAnodVw81oQ
mMhPijufrY6NSY/79jZdT3D5T1Qzz6KmHYxhuTBC8knRPaHx6x54pjD4ikiJxz69
DdhyBKYA5WKkEz+etoYl3NH/Ovz1DuQO97hmkP5PwlQqf2Fu50u/QH51MAJbu5Eb
-----END CERTIFICATE-----
End

  SERVER_CERT = <<'End'
Certificate:
    Data:
        Version: 3 (0x2)
        Serial Number: 1 (0x1)
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: C=JP, ST=Tokyo, O=RubyTest, CN=Ruby Test CA
        Validity
            Not Before: Jan  1 00:00:00 2009 GMT
            Not After : Dec 31 23:59:59 2049 GMT
        Subject: C=JP, ST=Tokyo, O=RubyTest, CN=127.0.0.1
        Subject Public Key Info:
            Public Key Algorithm: rsaEncryption
                RSA Public-Key: (2048 bit)
                Modulus:
                    00:cb:b3:71:95:12:70:fc:db:d4:a9:a7:66:d6:d3:
                    09:dd:06:80:19:e1:f2:d6:1e:31:b6:6b:20:75:51:
                    dc:a7:37:a9:ac:5b:57:5d:69:36:b6:de:1d:2c:f6:
                    44:64:f8:e8:d6:f0:da:38:6a:ba:c2:b1:9e:dc:bb:
                    79:94:e0:25:0c:ce:76:87:17:5d:79:9e:14:9e:bd:
                    4c:0d:aa:74:10:3a:96:ef:76:82:d5:72:16:b5:c1:
                    ac:17:2d:90:83:73:5c:d7:a6:f5:36:0f:4c:55:f3:
                    30:5d:19:dc:01:0e:f8:e6:fe:a5:ad:52:88:59:dc:
                    4a:07:ed:a2:eb:a1:01:63:c4:8a:92:ba:06:80:9b:
                    0d:85:f2:9f:f9:70:ac:d7:ad:f0:7a:3f:b8:92:2a:
                    33:ca:69:d0:01:65:5d:31:38:1d:f6:1f:b2:17:07:
                    7e:ac:88:67:a6:c4:5f:3e:93:94:61:e6:e4:49:9d:
                    ba:d4:d2:e8:e3:93:d1:66:79:c5:e3:1d:f8:5a:50:
                    54:58:3d:04:b0:fd:65:d1:b3:8a:b5:8a:30:5f:b2:
                    dc:34:1a:14:f7:74:4c:03:29:97:63:5a:d7:de:bb:
                    eb:7f:4a:2a:90:59:c0:2b:47:09:82:8f:75:de:14:
                    3f:bc:78:9a:69:25:80:5b:6c:a0:65:12:0d:29:61:
                    ac:f9
                Exponent: 65537 (0x10001)
        X509v3 extensions:
            X509v3 Basic Constraints:
                CA:FALSE
            Netscape Comment:
                OpenSSL Generated Certificate
            X509v3 Subject Key Identifier:
                EC:6B:7C:79:B8:3B:11:1D:42:F3:9A:2A:CF:9A:15:59:D7:F9:D8:C6
            X509v3 Authority Key Identifier:
                keyid:A0:7E:0B:AD:A3:AD:37:D7:21:0B:75:6F:8A:90:5F:8C:C9:69:DF:98

    Signature Algorithm: sha256WithRSAEncryption
         29:14:db:71:e9:a0:86:f8:cc:4d:e4:8a:76:78:a7:ff:4e:94:
         b4:4d:92:dc:57:9a:52:64:46:27:15:8b:4f:2a:18:a7:0d:fc:
         d2:75:ce:4e:49:97:0b:46:71:57:23:e3:a5:c0:c5:71:94:fc:
         f2:1d:3b:06:93:82:03:59:56:d4:fb:09:06:08:b4:97:50:33:
         cf:58:89:dd:91:31:07:26:9a:7e:7f:8d:71:de:09:dc:4f:e5:
         6b:a3:10:71:d4:50:24:43:a0:1c:f5:2a:d9:1a:fb:e3:d6:f1:
         bc:6b:42:67:16:b4:3b:31:f4:ec:03:7d:78:e2:64:16:57:6d:
         ba:7c:0c:e1:14:b2:7c:75:4e:2b:09:3e:86:e4:aa:cc:7e:5c:
         2b:bd:8d:26:4d:49:36:74:86:fe:c5:a6:15:4a:af:e8:b4:4e:
         d5:f2:e1:59:c2:fb:7e:c3:c4:f1:63:d8:c2:b0:9a:ae:31:96:
         90:c3:09:d0:ce:2e:31:90:d7:83:dd:ac:31:cc:f7:87:41:08:
         92:33:28:52:fa:2d:9e:ad:ae:6a:9f:c3:be:ce:c1:a6:e4:16:
         2f:69:34:40:86:b6:10:21:0e:31:69:81:9e:fc:fd:c3:06:25:
         65:37:d3:d9:4a:20:84:aa:e7:0e:60:7c:bf:3f:88:67:ac:e5:
         8c:e0:61:d6
-----BEGIN CERTIFICATE-----
MIIDgTCCAmmgAwIBAgIBATANBgkqhkiG9w0BAQsFADBHMQswCQYDVQQGEwJKUDEO
MAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRUwEwYDVQQDDAxSdWJ5
IFRlc3QgQ0EwHhcNMDkwMTAxMDAwMDAwWhcNNDkxMjMxMjM1OTU5WjBEMQswCQYD
VQQGEwJKUDEOMAwGA1UECAwFVG9reW8xETAPBgNVBAoMCFJ1YnlUZXN0MRIwEAYD
VQQDDAkxMjcuMC4wLjEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDL
s3GVEnD829Spp2bW0wndBoAZ4fLWHjG2ayB1UdynN6msW1ddaTa23h0s9kRk+OjW
8No4arrCsZ7cu3mU4CUMznaHF115nhSevUwNqnQQOpbvdoLVcha1wawXLZCDc1zX
pvU2D0xV8zBdGdwBDvjm/qWtUohZ3EoH7aLroQFjxIqSugaAmw2F8p/5cKzXrfB6
P7iSKjPKadABZV0xOB32H7IXB36siGemxF8+k5Rh5uRJnbrU0ujjk9FmecXjHfha
UFRYPQSw/WXRs4q1ijBfstw0GhT3dEwDKZdjWtfeu+t/SiqQWcArRwmCj3XeFD+8
eJppJYBbbKBlEg0pYaz5AgMBAAGjezB5MAkGA1UdEwQCMAAwLAYJYIZIAYb4QgEN
BB8WHU9wZW5TU0wgR2VuZXJhdGVkIENlcnRpZmljYXRlMB0GA1UdDgQWBBTsa3x5
uDsRHULzmirPmhVZ1/nYxjAfBgNVHSMEGDAWgBSgfguto6031yELdW+KkF+MyWnf
mDANBgkqhkiG9w0BAQsFAAOCAQEAKRTbcemghvjMTeSKdnin/06UtE2S3FeaUmRG
JxWLTyoYpw380nXOTkmXC0ZxVyPjpcDFcZT88h07BpOCA1lW1PsJBgi0l1Azz1iJ
3ZExByaafn+Ncd4J3E/la6MQcdRQJEOgHPUq2Rr749bxvGtCZxa0OzH07AN9eOJk
FldtunwM4RSyfHVOKwk+huSqzH5cK72NJk1JNnSG/sWmFUqv6LRO1fLhWcL7fsPE
8WPYwrCarjGWkMMJ0M4uMZDXg92sMcz3h0EIkjMoUvotnq2uap/Dvs7BpuQWL2k0
QIa2ECEOMWmBnvz9wwYlZTfT2UoghKrnDmB8vz+IZ6zljOBh1g==
-----END CERTIFICATE-----
End

  SERVER_KEY = <<'End'
RSA Private-Key: (2048 bit, 2 primes)
modulus:
    00:cb:b3:71:95:12:70:fc:db:d4:a9:a7:66:d6:d3:
    09:dd:06:80:19:e1:f2:d6:1e:31:b6:6b:20:75:51:
    dc:a7:37:a9:ac:5b:57:5d:69:36:b6:de:1d:2c:f6:
    44:64:f8:e8:d6:f0:da:38:6a:ba:c2:b1:9e:dc:bb:
    79:94:e0:25:0c:ce:76:87:17:5d:79:9e:14:9e:bd:
    4c:0d:aa:74:10:3a:96:ef:76:82:d5:72:16:b5:c1:
    ac:17:2d:90:83:73:5c:d7:a6:f5:36:0f:4c:55:f3:
    30:5d:19:dc:01:0e:f8:e6:fe:a5:ad:52:88:59:dc:
    4a:07:ed:a2:eb:a1:01:63:c4:8a:92:ba:06:80:9b:
    0d:85:f2:9f:f9:70:ac:d7:ad:f0:7a:3f:b8:92:2a:
    33:ca:69:d0:01:65:5d:31:38:1d:f6:1f:b2:17:07:
    7e:ac:88:67:a6:c4:5f:3e:93:94:61:e6:e4:49:9d:
    ba:d4:d2:e8:e3:93:d1:66:79:c5:e3:1d:f8:5a:50:
    54:58:3d:04:b0:fd:65:d1:b3:8a:b5:8a:30:5f:b2:
    dc:34:1a:14:f7:74:4c:03:29:97:63:5a:d7:de:bb:
    eb:7f:4a:2a:90:59:c0:2b:47:09:82:8f:75:de:14:
    3f:bc:78:9a:69:25:80:5b:6c:a0:65:12:0d:29:61:
    ac:f9
publicExponent: 65537 (0x10001)
privateExponent:
    12:be:d5:b2:01:3b:72:99:8c:4d:7c:81:43:3d:b2:
    87:ab:84:78:5d:49:aa:98:a6:bc:81:c9:3f:e2:a3:
    aa:a3:bd:b2:85:c9:59:68:48:47:b5:d2:fb:83:42:
    32:04:91:f0:cd:c3:57:33:c3:32:0d:84:70:0d:b4:
    97:95:b4:f3:23:c0:d6:97:b8:db:6b:47:bc:7f:f1:
    12:c4:df:df:6a:74:df:5e:89:95:b8:e5:0c:1e:e1:
    86:54:84:1b:04:af:c3:8c:b2:be:21:d4:45:88:96:
    a7:ca:ac:6b:50:84:69:45:7f:db:9e:5f:bb:dd:40:
    d6:cf:f0:91:3c:84:d3:38:65:c9:15:f7:9e:37:aa:
    1a:2e:bc:16:b6:95:be:bc:af:45:76:ba:ad:99:f6:
    ef:6a:e8:fd:f0:31:89:19:c4:04:67:a1:ec:c4:79:
    59:08:77:ab:0b:65:88:88:02:b1:38:5c:80:4e:27:
    78:b2:a5:bd:b5:ad:d5:9c:4c:ea:ad:db:05:56:25:
    70:28:da:22:fb:d8:de:8c:3b:78:fe:3e:cf:ed:1b:
    f9:97:c6:b6:4a:bf:60:08:8f:dc:85:5e:b1:49:ab:
    87:8b:68:72:f4:6a:3f:bc:db:a3:6c:f7:e8:b0:15:
    bb:4b:ba:37:49:a2:d1:7c:f8:4f:1b:05:11:22:d9:
    81
prime1:
    00:fb:d2:cb:14:61:00:c1:7a:83:ba:fe:79:97:a2:
    4d:5a:ea:40:78:96:6e:d2:be:71:5b:c6:2c:1f:c9:
    18:48:6b:ae:20:86:87:b5:08:0b:17:69:ca:93:cd:
    00:36:22:51:7b:d5:2d:8c:0c:0e:de:bc:86:a8:07:
    0e:c5:57:e4:df:be:ed:7d:cc:b1:a4:d6:a8:2b:00:
    65:2a:69:30:5e:dc:6d:6d:c4:c8:7e:20:34:eb:6f:
    5e:cf:b3:b8:2e:8d:56:31:44:a8:17:ea:be:65:19:
    ff:da:14:e0:0c:73:56:14:08:47:4c:5b:79:51:74:
    5d:bc:e7:fe:01:2f:55:27:69
prime2:
    00:cf:14:54:47:bb:5f:5d:d6:2b:2d:ed:a6:8a:6f:
    36:fc:47:5e:9f:84:ae:aa:1f:f8:44:50:91:15:f5:
    ed:9d:29:d9:2b:2a:19:66:56:2e:96:15:b5:8e:a9:
    7f:89:27:21:b5:57:55:7e:2a:c5:8c:93:fe:f6:0a:
    a5:17:15:91:91:b3:7d:35:1a:d5:9a:2e:b8:0d:ad:
    e6:97:6d:83:a3:27:29:ee:00:74:ef:57:34:f3:07:
    ad:12:43:37:0c:5c:b7:26:34:bc:4e:3a:43:65:6b:
    0c:b8:23:ac:77:fd:b2:23:eb:7b:65:70:f6:96:c4:
    17:2c:aa:24:b8:a5:5e:b7:11
exponent1:
    00:92:32:ae:f4:05:dd:0a:76:b6:43:b9:b9:9d:ee:
    fc:39:ec:05:c1:fc:94:1a:85:b6:0a:31:e3:2c:10:
    f3:a8:17:db:df:c6:3a:c3:3f:08:31:6f:99:cc:75:
    17:ca:55:e2:38:a2:6a:ef:03:91:1e:7f:15:2e:37:
    ea:bb:67:6b:d8:fa:5f:a6:c9:4f:d9:03:46:5e:b0:
    bc:0b:03:46:b1:cc:07:3b:d3:23:13:16:5f:a2:cf:
    e5:9b:70:1b:5d:eb:70:3e:ea:3d:2c:a5:7c:23:f6:
    14:33:e8:2a:ab:0f:ca:c9:96:84:ce:2f:cd:1f:1d:
    0f:ce:bc:61:1b:0e:ff:c1:01
exponent2:
    00:9e:0b:f3:03:48:73:d1:e7:9a:cf:13:f9:ae:e0:
    91:03:dc:e8:d0:30:f1:2a:30:fa:48:11:81:9a:54:
    37:c5:62:e2:37:fa:8a:a6:3b:92:94:c3:fe:ec:e2:
    5a:cf:70:09:5f:21:47:c3:e2:9b:21:de:f6:92:0c:
    af:d1:bd:89:7b:bd:95:0b:49:ee:cb:1d:6b:26:2d:
    9a:b7:ea:42:b4:ec:38:29:49:39:f6:4e:05:c0:93:
    14:39:c3:09:29:ab:3d:b1:b0:40:24:28:7d:b5:d3:
    0d:43:21:1f:09:f9:9b:d3:a4:6f:6a:8d:db:f6:57:
    b5:24:46:bb:7e:1d:e0:fb:31
coefficient:
    10:93:1d:c8:33:a5:c1:d3:84:6a:22:68:e5:60:cc:
    9c:27:0a:52:0b:58:a3:0c:83:f4:f4:46:09:0c:a1:
    41:a6:ea:bf:80:9d:0e:5d:d8:3d:25:00:c5:a1:35:
    7a:8c:ea:95:16:94:c3:7c:8f:2b:e0:53:ea:66:ae:
    19:be:55:04:3d:ee:e2:4b:a8:69:1b:7e:d8:09:7f:
    ed:7c:ee:95:88:10:dc:4b:5b:bf:81:a4:e8:dc:7e:
    4f:e5:c3:90:c4:e5:5a:90:10:32:d6:08:b5:1f:5d:
    09:18:d8:44:28:e4:c4:c7:07:75:9b:9b:b3:80:86:
    68:9d:fe:68:f3:4d:db:66
writing RSA key
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAy7NxlRJw/NvUqadm1tMJ3QaAGeHy1h4xtmsgdVHcpzeprFtX
XWk2tt4dLPZEZPjo1vDaOGq6wrGe3Lt5lOAlDM52hxddeZ4Unr1MDap0EDqW73aC
1XIWtcGsFy2Qg3Nc16b1Ng9MVfMwXRncAQ745v6lrVKIWdxKB+2i66EBY8SKkroG
gJsNhfKf+XCs163wej+4kiozymnQAWVdMTgd9h+yFwd+rIhnpsRfPpOUYebkSZ26
1NLo45PRZnnF4x34WlBUWD0EsP1l0bOKtYowX7LcNBoU93RMAymXY1rX3rvrf0oq
kFnAK0cJgo913hQ/vHiaaSWAW2ygZRINKWGs+QIDAQABAoIBABK+1bIBO3KZjE18
gUM9soerhHhdSaqYpryByT/io6qjvbKFyVloSEe10vuDQjIEkfDNw1czwzINhHAN
tJeVtPMjwNaXuNtrR7x/8RLE399qdN9eiZW45Qwe4YZUhBsEr8OMsr4h1EWIlqfK
rGtQhGlFf9ueX7vdQNbP8JE8hNM4ZckV9543qhouvBa2lb68r0V2uq2Z9u9q6P3w
MYkZxARnoezEeVkId6sLZYiIArE4XIBOJ3iypb21rdWcTOqt2wVWJXAo2iL72N6M
O3j+Ps/tG/mXxrZKv2AIj9yFXrFJq4eLaHL0aj+826Ns9+iwFbtLujdJotF8+E8b
BREi2YECgYEA+9LLFGEAwXqDuv55l6JNWupAeJZu0r5xW8YsH8kYSGuuIIaHtQgL
F2nKk80ANiJRe9UtjAwO3ryGqAcOxVfk377tfcyxpNaoKwBlKmkwXtxtbcTIfiA0
629ez7O4Lo1WMUSoF+q+ZRn/2hTgDHNWFAhHTFt5UXRdvOf+AS9VJ2kCgYEAzxRU
R7tfXdYrLe2mim82/Eden4Suqh/4RFCRFfXtnSnZKyoZZlYulhW1jql/iSchtVdV
firFjJP+9gqlFxWRkbN9NRrVmi64Da3ml22Doycp7gB071c08wetEkM3DFy3JjS8
TjpDZWsMuCOsd/2yI+t7ZXD2lsQXLKokuKVetxECgYEAkjKu9AXdCna2Q7m5ne78
OewFwfyUGoW2CjHjLBDzqBfb38Y6wz8IMW+ZzHUXylXiOKJq7wORHn8VLjfqu2dr
2PpfpslP2QNGXrC8CwNGscwHO9MjExZfos/lm3AbXetwPuo9LKV8I/YUM+gqqw/K
yZaEzi/NHx0PzrxhGw7/wQECgYEAngvzA0hz0eeazxP5ruCRA9zo0DDxKjD6SBGB
mlQ3xWLiN/qKpjuSlMP+7OJaz3AJXyFHw+KbId72kgyv0b2Je72VC0nuyx1rJi2a
t+pCtOw4KUk59k4FwJMUOcMJKas9sbBAJCh9tdMNQyEfCfmb06Rvao3b9le1JEa7
fh3g+zECgYAQkx3IM6XB04RqImjlYMycJwpSC1ijDIP09EYJDKFBpuq/gJ0OXdg9
JQDFoTV6jOqVFpTDfI8r4FPqZq4ZvlUEPe7iS6hpG37YCX/tfO6ViBDcS1u/gaTo
3H5P5cOQxOVakBAy1gi1H10JGNhEKOTExwd1m5uzgIZonf5o803bZg==
-----END RSA PRIVATE KEY-----
End

  DHPARAMS = <<'End'
    DH Parameters: (2048 bit)
        prime:
            00:ec:4e:a4:06:b6:22:ca:f9:8a:00:cc:d0:ee:2f:
            16:bf:05:64:f5:8f:fe:7f:c4:bb:b0:24:cd:ef:5d:
            8a:90:ad:dc:a9:dd:63:84:90:d8:25:ba:d8:78:d5:
            77:91:42:0a:84:fc:56:1e:13:9b:1c:aa:43:d5:1f:
            38:52:92:fe:b3:66:f9:e7:e8:8c:77:a1:a6:2f:b3:
            98:98:d2:13:fc:57:1c:2a:14:dc:bd:e6:9b:54:19:
            99:4f:ce:81:64:a6:32:7f:8e:61:50:5f:45:3a:e5:
            0c:f7:13:f3:b8:ad:d5:77:ca:09:42:f7:d8:30:27:
            7b:2c:f0:b4:b5:a0:04:96:34:0b:47:81:1d:7f:c1:
            3a:62:86:8e:7d:f8:13:7f:9a:b1:8b:09:23:9e:55:
            59:41:cd:f0:86:09:c4:b7:d1:69:54:cb:d0:f5:e9:
            27:c9:e1:81:e4:a1:df:6b:20:1c:df:e8:54:02:f2:
            37:fc:2a:f7:d5:b3:6f:79:7e:70:22:78:79:18:3c:
            75:14:68:4a:05:9f:ac:d4:7f:9a:79:db:9d:0a:6e:
            ec:0a:04:70:bf:c9:4a:59:81:a2:1f:33:9b:4a:66:
            bc:03:ce:8a:1b:e3:03:ec:ba:39:26:ab:90:dc:39:
            41:a1:d8:f7:20:3c:8f:af:12:2f:f7:a9:6f:44:f1:
            6d:03
        generator: 2 (0x2)
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA7E6kBrYiyvmKAMzQ7i8WvwVk9Y/+f8S7sCTN712KkK3cqd1jhJDY
JbrYeNV3kUIKhPxWHhObHKpD1R84UpL+s2b55+iMd6GmL7OYmNIT/FccKhTcveab
VBmZT86BZKYyf45hUF9FOuUM9xPzuK3Vd8oJQvfYMCd7LPC0taAEljQLR4Edf8E6
YoaOffgTf5qxiwkjnlVZQc3whgnEt9FpVMvQ9eknyeGB5KHfayAc3+hUAvI3/Cr3
1bNveX5wInh5GDx1FGhKBZ+s1H+aedudCm7sCgRwv8lKWYGiHzObSma8A86KG+MD
7Lo5JquQ3DlBodj3IDyPrxIv96lvRPFtAwIBAg==
-----END DH PARAMETERS-----
End
  end
end
