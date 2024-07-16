# frozen_string_literal: false
begin
  require 'net/https'
rescue LoadError
end
require 'test/unit'

class HTTPSProxyTest < Test::Unit::TestCase
  def test_https_proxy_authentication
    begin
      OpenSSL
    rescue LoadError
      omit 'autoload problem. see [ruby-dev:45021][Bug #5786]'
    end

    TCPServer.open("127.0.0.1", 0) {|serv|
      _, port, _, _ = serv.addr
      client_thread = Thread.new {
        proxy = Net::HTTP.Proxy("127.0.0.1", port, 'user', 'password')
        http = proxy.new("foo.example.org", 8000)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        begin
          http.start
        rescue EOFError
        end
      }
      server_thread = Thread.new {
        sock = serv.accept
        begin
          proxy_request = sock.gets("\r\n\r\n")
          assert_equal(
            "CONNECT foo.example.org:8000 HTTP/1.1\r\n" +
            "Host: foo.example.org:8000\r\n" +
            "Proxy-Authorization: Basic dXNlcjpwYXNzd29yZA==\r\n" +
            "\r\n",
            proxy_request,
            "[ruby-dev:25673]")
        ensure
          sock.close
        end
      }
      assert_join_threads([client_thread, server_thread])
    }
  end


  def read_fixture(key)
    File.read(File.expand_path("../fixtures/#{key}", __dir__))
  end

  def test_https_proxy_ssl_connection
    begin
      OpenSSL
    rescue LoadError
      omit 'autoload problem. see [ruby-dev:45021][Bug #5786]'
    end

    tcpserver = TCPServer.new("127.0.0.1", 0)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.key = OpenSSL::PKey.read(read_fixture("server.key"))
    ctx.cert = OpenSSL::X509::Certificate.new(read_fixture("server.crt"))
    serv = OpenSSL::SSL::SSLServer.new(tcpserver, ctx)

    _, port, _, _ = serv.addr
    client_thread = Thread.new {
      proxy = Net::HTTP.Proxy("127.0.0.1", port, 'user', 'password', true)
      http = proxy.new("foo.example.org", 8000)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      begin
        http.start
      rescue EOFError
      end
    }
    server_thread = Thread.new {
      sock = serv.accept
      begin
        proxy_request = sock.gets("\r\n\r\n")
        assert_equal(
          "CONNECT foo.example.org:8000 HTTP/1.1\r\n" +
          "Host: foo.example.org:8000\r\n" +
          "Proxy-Authorization: Basic dXNlcjpwYXNzd29yZA==\r\n" +
          "\r\n",
          proxy_request,
          "[ruby-core:96672]")
      ensure
        sock.close
      end
    }
    assert_join_threads([client_thread, server_thread])
  end
end if defined?(OpenSSL)
