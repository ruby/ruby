require "test/unit"
require "webrick"
require "webrick/ssl"
require_relative "utils"
require 'timeout'

class TestWEBrickSSLServer < Test::Unit::TestCase
  class Echo < WEBrick::GenericServer
    def run(sock)
      while line = sock.gets
        sock << line
      end
    end
  end

  def test_self_signed_cert_server
    assert_self_signed_cert(
      :SSLEnable => true,
      :SSLCertName => [["C", "JP"], ["O", "www.ruby-lang.org"], ["CN", "Ruby"]],
    )
  end

  def assert_self_signed_cert(config)
    TestWEBrick.start_server(Echo, config){|server, addr, port, log|
      io = TCPSocket.new(addr, port)
      sock = OpenSSL::SSL::SSLSocket.new(io)
      sock.connect
      sock.puts(server.ssl_context.cert.subject.to_s)
      assert_equal("/C=JP/O=www.ruby-lang.org/CN=Ruby\n", sock.gets, log.call)
      sock.close
      io.close
    }
  end

  def test_slow_connect
    poke = lambda do |io, msg|
      begin
        sock = OpenSSL::SSL::SSLSocket.new(io)
        sock.connect
        sock.puts(msg)
        assert_equal "#{msg}\n", sock.gets, msg
      ensure
        sock&.close
        io.close
      end
    end
    config = {
      :SSLEnable => true,
      :SSLCertName => [["C", "JP"], ["O", "www.ruby-lang.org"], ["CN", "Ruby"]],
    }
    Timeout.timeout(10) do
      TestWEBrick.start_server(Echo, config) do |server, addr, port, log|
        outer = TCPSocket.new(addr, port)
        inner = TCPSocket.new(addr, port)
        poke.call(inner, 'fast TLS negotiation')
        poke.call(outer, 'slow TLS negotiation')
      end
    end
  end
end
