begin
  require "openssl"
  require File.join(File.dirname(__FILE__), "utils.rb")
rescue LoadError
end
require "rbconfig"
require "socket"
require "test/unit"
begin
  loadpath = $:.dup
  $:.replace($: | [File.expand_path("../ruby", File.dirname(__FILE__))])
  require 'envutil'
ensure
  $:.replace(loadpath)
end

if defined?(OpenSSL)

class OpenSSL::TestSSL < Test::Unit::TestCase
  RUBY = EnvUtil.rubybin
  SSL_SERVER = File.join(File.dirname(__FILE__), "ssl_server.rb")
  PORT = 20443
  ITERATIONS = ($0 == __FILE__) ? 100 : 10

  def setup
    @ca_key  = OpenSSL::TestUtils::TEST_KEY_RSA2048
    @svr_key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    @cli_key = OpenSSL::TestUtils::TEST_KEY_DSA256
    @ca  = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=CA")
    @svr = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")
    @cli = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=localhost")

    now = Time.at(Time.now.to_i)
    ca_exts = [
      ["basicConstraints","CA:TRUE",true],
      ["keyUsage","cRLSign,keyCertSign",true],
    ]
    ee_exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
    ]
    @ca_cert  = issue_cert(@ca, @ca_key, 1, now, now+3600, ca_exts,
                           nil, nil, OpenSSL::Digest::SHA1.new)
    @svr_cert = issue_cert(@svr, @svr_key, 2, now, now+1800, ee_exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    @cli_cert = issue_cert(@cli, @cli_key, 3, now, now+1800, ee_exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    @server = nil
  end

  def teardown
  end

  def issue_cert(*arg)
    OpenSSL::TestUtils.issue_cert(*arg)
  end

  def issue_crl(*arg)
    OpenSSL::TestUtils.issue_crl(*arg)
  end

  def start_server(port0, verify_mode, start_immediately, &block)
    server = nil
    begin
      cmd = [RUBY]
      cmd << "-d" if $DEBUG
      cmd << SSL_SERVER << port0.to_s << verify_mode.to_s
      cmd << (start_immediately ? "yes" : "no")
      server = IO.popen(cmd, "w+")
      server.write(@ca_cert.to_pem)
      server.write(@svr_cert.to_pem)
      server.write(@svr_key.to_pem)
      pid = Integer(server.gets)
      if port = server.gets
        if $DEBUG
          $stderr.printf("%s started: pid=%d port=%d\n", SSL_SERVER, pid, port)
        end
        block.call(server, port.to_i)
      end
    ensure
      if server
        Process.kill(:KILL, pid)
        server.close
      end
    end
  end

  def starttls(ssl)
    ssl.puts("STARTTLS")

    sleep 1   # When this line is eliminated, process on Cygwin blocks
              # forever at ssl.connect. But I don't know why it does.

    ssl.connect
  end

  def test_connect_and_close
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      assert(ssl.connect)
      ssl.close
      assert(!sock.closed?)
      sock.close

      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true  # !!
      assert(ssl.connect)
      ssl.close
      assert(sock.closed?)
    }
  end

  def test_read_and_write
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect

      # syswrite and sysread
      ITERATIONS.times{|i|
        str = "x" * 100 + "\n"
        ssl.syswrite(str)
        assert_equal(str, ssl.sysread(str.size))

        str = "x" * i * 100 + "\n"
        buf = ""
        ssl.syswrite(str)
        assert_equal(buf.object_id, ssl.sysread(str.size, buf).object_id)
        assert_equal(str, buf)
      }

      # puts and gets
      ITERATIONS.times{
        str = "x" * 100 + "\n"
        ssl.puts(str)
        assert_equal(str, ssl.gets)

        str = "x" * 100
        ssl.puts(str)
        assert_equal(str, ssl.gets("\n", 100))
        assert_equal("\n", ssl.gets)
      }

      # read and write
      ITERATIONS.times{|i|
        str = "x" * 100 + "\n"
        ssl.write(str)
        assert_equal(str, ssl.read(str.size))

        str = "x" * i * 100 + "\n"
        buf = ""
        ssl.write(str)
        assert_equal(buf.object_id, ssl.read(str.size, buf).object_id)
        assert_equal(str, buf)
      }

      ssl.close
    }
  end

  def test_client_auth
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(PORT, vflag, true){|server, port|
      assert_raises(OpenSSL::SSL::SSLError){
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.connect
      }

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = @cli_key
      ctx.cert = @cli_cert
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      ssl.connect
      ssl.puts("foo")
      assert_equal("foo\n", ssl.gets)
      ssl.close

      called = nil
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.client_cert_cb = Proc.new{|ssl|
        called = true
        [@cli_cert, @cli_key]
      }
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      ssl.connect
      assert(called)
      ssl.puts("foo")
      assert_equal("foo\n", ssl.gets)
      ssl.close
    }
  end

  def test_starttls
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, false){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      str = "x" * 1000 + "\n"

      ITERATIONS.times{
        ssl.puts(str)
        assert_equal(str, ssl.gets)
      }

      starttls(ssl)

      ITERATIONS.times{
        ssl.puts(str)
        assert_equal(str, ssl.gets)
      }

      ssl.close
    }
  end

  def test_parallel
    GC.start
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      ssls = []
      10.times{
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.connect
        ssl.sync_close = true
        ssls << ssl
      }
      str = "x" * 1000 + "\n"
      ITERATIONS.times{
        ssls.each{|ssl|
          ssl.puts(str)
          assert_equal(str, ssl.gets)
        }
      }
      ssls.each{|ssl| ssl.close }
    }
  end

  def test_verify_result
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
      assert_equal(OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN, ssl.verify_result)

      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(
        :verify_callback => Proc.new do |preverify_ok, store_ctx|
          store_ctx.error = OpenSSL::X509::V_OK
          true
        end
      )
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.connect
      assert_equal(OpenSSL::X509::V_OK, ssl.verify_result)

      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(
        :verify_callback => Proc.new do |preverify_ok, store_ctx|
          store_ctx.error = OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION
          false
        end
      )
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
      assert_equal(OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION, ssl.verify_result)
    }
  end

  def test_sslctx_set_params
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      assert_equal(OpenSSL::SSL::VERIFY_PEER, ctx.verify_mode)
      assert_equal(OpenSSL::SSL::OP_ALL, ctx.options)
      ciphers = ctx.ciphers
      ciphers_versions = ciphers.collect{|_, v, _, _| v }
      ciphers_names = ciphers.collect{|v, _, _, _| v }
      assert(ciphers_names.all?{|v| /ADH/ !~ v })
      assert(ciphers_versions.all?{|v| /SSLv2/ !~ v })
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
      assert_equal(OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN, ssl.verify_result)
    }
  end

  def test_post_connection_check
    sslerr = OpenSSL::SSL::SSLError

    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.connect
      assert_raises(sslerr){ssl.post_connection_check("localhost.localdomain")}
      assert_raises(sslerr){ssl.post_connection_check("127.0.0.1")}
      assert(ssl.post_connection_check("localhost"))
      assert_raises(sslerr){ssl.post_connection_check("foo.example.com")}

      cert = ssl.peer_cert
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "localhost.localdomain"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "127.0.0.1"))
      assert(OpenSSL::SSL.verify_certificate_identity(cert, "localhost"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "foo.example.com"))
    }

    now = Time.now
    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:localhost.localdomain",false],
      ["subjectAltName","IP:127.0.0.1",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 4, now, now+1800, exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.connect
      assert(ssl.post_connection_check("localhost.localdomain"))
      assert(ssl.post_connection_check("127.0.0.1"))
      assert_raises(sslerr){ssl.post_connection_check("localhost")}
      assert_raises(sslerr){ssl.post_connection_check("foo.example.com")}

      cert = ssl.peer_cert
      assert(OpenSSL::SSL.verify_certificate_identity(cert, "localhost.localdomain"))
      assert(OpenSSL::SSL.verify_certificate_identity(cert, "127.0.0.1"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "localhost"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "foo.example.com"))
    }

    now = Time.now
    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:*.localdomain",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 5, now, now+1800, exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.connect
      assert(ssl.post_connection_check("localhost.localdomain"))
      assert_raises(sslerr){ssl.post_connection_check("127.0.0.1")}
      assert_raises(sslerr){ssl.post_connection_check("localhost")}
      assert_raises(sslerr){ssl.post_connection_check("foo.example.com")}
      cert = ssl.peer_cert
      assert(OpenSSL::SSL.verify_certificate_identity(cert, "localhost.localdomain"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "127.0.0.1"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "localhost"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "foo.example.com"))
    }
  end
end

end
