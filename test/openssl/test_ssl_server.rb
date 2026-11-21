# frozen_string_literal: true
require_relative "utils"

return unless defined?(OpenSSL::SSL)

class OpenSSL::TestSSLServer < OpenSSL::SSLTestCase
  def test_tcpserver
    tcps = TCPServer.new("127.0.0.1", 0)
    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(@svr_cert, @svr_key)
    server = OpenSSL::SSL::SSLServer.new(tcps, sctx)
    assert_same(tcps, server.to_io)
    assert_kind_of(String, sctx.session_id_context)
    th = Thread.start do
      sssl = server.accept
      sssl.puts(sssl.gets)
    ensure
      sssl&.close
    end
    server_connect(tcps.local_address.ip_port) do |ssl|
      assert_equal(@svr_cert.to_der, ssl.peer_cert.to_der)
      ssl.puts("abc")
      assert_equal("abc\n", ssl.gets)
    end
    th.join
    server.close
    assert_predicate(tcps, :closed?)
  end

  def test_ctx_frozen
    tcps = TCPServer.new("127.0.0.1", 0)
    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(@svr_cert, @svr_key)
    sctx.setup
    server = OpenSSL::SSL::SSLServer.new(tcps, sctx)
    assert_nil(sctx.session_id_context)
    th = Thread.start do
      sssl = server.accept
      sssl.puts(sssl.gets)
    ensure
      sssl&.close
    end
    server_connect(tcps.local_address.ip_port) do |ssl|
      assert_equal(@svr_cert.to_der, ssl.peer_cert.to_der)
      ssl.puts("abc")
      assert_equal("abc\n", ssl.gets)
    end
    th.join
    server.close
  end

  private

  def server_connect(port, ctx = nil)
    sock = TCPSocket.new("127.0.0.1", port)
    ssl = ctx ? OpenSSL::SSL::SSLSocket.new(sock, ctx) : OpenSSL::SSL::SSLSocket.new(sock)
    ssl.sync_close = true
    ssl.connect
    yield ssl if block_given?
  ensure
    if ssl
      ssl.close
    elsif sock
      sock.close
    end
  end
end
