begin
  require "openssl"
  require File.join(File.dirname(__FILE__), "utils.rb")
rescue LoadError
end
require "rbconfig"
require "socket"
require "test/unit"
require 'tempfile'

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

  def choose_port(port)
    tcps = nil
    100.times{ |i|
      begin
        tcps = TCPServer.new("127.0.0.1", port+i)
        port = port + i
        break
      rescue Errno::EADDRINUSE
        next
      end
    }
    return tcps, port
  end

  def readwrite_loop(ctx, ssl)
    while line = ssl.gets
      if line =~ /^STARTTLS$/
        ssl.accept
        next
      end
      ssl.write(line)
    end
  rescue OpenSSL::SSL::SSLError
  rescue IOError
  ensure
    ssl.close rescue nil
  end

  def server_loop(ctx, ssls, server_proc)
    loop do
      ssl = nil
      begin
        ssl = ssls.accept
      rescue OpenSSL::SSL::SSLError
        retry
      end

      Thread.start do
        Thread.current.abort_on_exception = true
        server_proc.call(ctx, ssl)
      end
    end
  rescue Errno::EBADF, IOError, Errno::EINVAL, Errno::ECONNABORTED
  end

  def start_server(port0, verify_mode, start_immediately, args = {}, &block)
    ctx_proc = args[:ctx_proc]
    server_proc = args[:server_proc]
    server_proc ||= method(:readwrite_loop)

    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    store.purpose = OpenSSL::X509::PURPOSE_SSL_CLIENT
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.cert_store = store
    #ctx.extra_chain_cert = [ ca_cert ]
    ctx.cert = @svr_cert
    ctx.key = @svr_key
    ctx.verify_mode = verify_mode
    ctx_proc.call(ctx) if ctx_proc

    Socket.do_not_reverse_lookup = true
    tcps, port = choose_port(port0)

    ssls = OpenSSL::SSL::SSLServer.new(tcps, ctx)
    ssls.start_immediately = start_immediately

    begin
      server = Thread.new do
        Thread.current.abort_on_exception = true
        server_loop(ctx, ssls, server_proc)
      end

      $stderr.printf("%s started: pid=%d port=%d\n", SSL_SERVER, $$, port) if $DEBUG

      block.call(server, port.to_i)
    ensure
      begin
        begin
          tcps.shutdown
        rescue Errno::ENOTCONN
          # when `Errno::ENOTCONN: Socket is not connected' on some platforms,
          # call #close instead of #shutdown.
          tcps.close
          tcps = nil
        end if (tcps)
        if (server)
          server.join(5)
          if server.alive?
            server.kill
            server.join
            flunk("TCPServer was closed and SSLServer is still alive") unless $!
          end
        end
      ensure
        tcps.close if (tcps)
      end
    end
  end

  def starttls(ssl)
    ssl.puts("STARTTLS")

    sleep 1   # When this line is eliminated, process on Cygwin blocks
              # forever at ssl.connect. But I don't know why it does.

    ssl.connect
  end

  def test_ctx_setup
    ctx = OpenSSL::SSL::SSLContext.new
    assert_equal(ctx.setup, true)
    assert_equal(ctx.setup, nil)
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

      assert_raise(ArgumentError) { ssl.sysread(-1) }

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

  def test_sysread_chunks
    args = {}
    args[:server_proc] = proc { |ctx, ssl|
      while line = ssl.gets
        if line =~ /^STARTTLS$/
          ssl.accept
          next
        end
        ssl.write("0" * 800)
        ssl.write("1" * 200)
        ssl.close
        break
      end
    }
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, args){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect
      ssl.syswrite("hello\n")
      assert_equal("0" * 200, ssl.sysread(200))
      assert_equal("0" * 200, ssl.sysread(200))
      assert_equal("0" * 200, ssl.sysread(200))
      assert_equal("0" * 200, ssl.sysread(200))
      assert_equal("1" * 200, ssl.sysread(200))
      ssl.close
    }
  end

  def test_sysread_buffer
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect
      ITERATIONS.times{|i|
        # the given buffer is cleared before concatenating.
        # NB: SSLSocket#readpartial depends sysread.
        str = "x" * i * 100 + "\n"
        ssl.syswrite(str)
        buf = "asdf"
        assert_equal(buf.object_id, ssl.sysread(0, buf).object_id)
        assert_equal("", buf)

        buf = "asdf"
        read = ssl.sysread(str.size, buf)
        assert(!read.empty?)
        assert_equal(buf.object_id, read.object_id)
        assert_equal(str, buf)

        ssl.syswrite(str)
        read = ssl.sysread(str.size, nil)
        assert(!read.empty?)
        assert_equal(str, read)
      }
      ssl.close
    }
  end

  def test_client_auth
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(PORT, vflag, true){|server, port|
      assert_raise(OpenSSL::SSL::SSLError){
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
      ctx.client_cert_cb = Proc.new{ |sslconn|
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

  def test_client_auth_with_server_store
    vflag = OpenSSL::SSL::VERIFY_PEER

    localcacert_file = Tempfile.open("cafile")
    localcacert_file << @ca_cert.to_pem
    localcacert_file.close
    localcacert_path = localcacert_file.path

    ssl_store = OpenSSL::X509::Store.new
    ssl_store.purpose = OpenSSL::X509::PURPOSE_ANY
    ssl_store.add_file(localcacert_path)

    args = {}
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.cert = @svr_cert
      server_ctx.key = @svr_key
      server_ctx.verify_mode = vflag
      server_ctx.cert_store = ssl_store
    }

    start_server(PORT, vflag, true, args){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.cert = @cli_cert
      ctx.key = @cli_key
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      ssl.connect
      ssl.puts("foo")
      assert_equal("foo\n", ssl.gets)
      ssl.close
      localcacert_file.unlink
    }
  end

  def test_client_crl_with_server_store
    vflag = OpenSSL::SSL::VERIFY_PEER

    localcacert_file = Tempfile.open("cafile")
    localcacert_file << @ca_cert.to_pem
    localcacert_file.close
    localcacert_path = localcacert_file.path

    ssl_store = OpenSSL::X509::Store.new
    ssl_store.purpose = OpenSSL::X509::PURPOSE_ANY
    ssl_store.add_file(localcacert_path)
    ssl_store.flags = OpenSSL::X509::V_FLAG_CRL_CHECK_ALL|OpenSSL::X509::V_FLAG_CRL_CHECK

    crl = issue_crl([], 1, Time.now, Time.now+1600, [],
                    @cli_cert, @ca_key, OpenSSL::Digest::SHA1.new)

    ssl_store.add_crl(OpenSSL::X509::CRL.new(crl.to_pem))

    args = {}
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.cert = @svr_cert
      server_ctx.key = @svr_key
      server_ctx.verify_mode = vflag
      server_ctx.cert_store = ssl_store
    }

    start_server(PORT, vflag, true, args){|s, p|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.cert = @cli_cert
      ctx.key = @cli_key
      assert_raise(OpenSSL::SSL::SSLError){
        sock = TCPSocket.new("127.0.0.1", p)
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.sync_close = true
        ssl.connect
        ssl.close
      }
      localcacert_file.unlink
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

  def test_extra_chain_cert
    start_server(PORT, OpenSSL::SSL::VERIFY_PEER, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
      assert_equal(OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN, ssl.verify_result)
    }
    # server returns a chain w/o root cert so the client verification fails
    # with UNABLE_TO_GET_ISSUER_CERT_LOCALLY not SELF_SIGNED_CERT_IN_CHAIN.
    args = {}
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.cert = @svr_cert
      server_ctx.key = @svr_key
      server_ctx.extra_chain_cert = [@svr_cert]
    }
    start_server(PORT, OpenSSL::SSL::VERIFY_PEER, true, args){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
      assert_equal(OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY, ssl.verify_result)
    }
  end

  def test_client_ca
    args = {}
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT

    # client_ca as a cert
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.cert = @svr_cert
      server_ctx.key = @svr_key
      server_ctx.client_ca = @ca_cert
    }
    start_server(PORT, vflag, true, args){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = @cli_key
      ctx.cert = @cli_cert
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      ssl.connect
      ssl.puts("foo")
      assert_equal("foo\n", ssl.gets)
    }

    # client_ca as an array
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.cert = @svr_cert
      server_ctx.key = @svr_key
      server_ctx.client_ca = [@ca_cert, @svr_cert]
    }
    start_server(PORT, vflag, true, args){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = @cli_key
      ctx.cert = @cli_cert
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      ssl.connect
      ssl.puts("foo")
      assert_equal("foo\n", ssl.gets)
    }
  end

  def test_sslctx_ssl_version_client
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      ctx.ssl_version = "TLSv1"
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_nothing_raised do
        ssl.connect
      end
      ssl.puts("hello TLSv1")
      ssl.close
      sock.close
      #
      sock = TCPSocket.new("127.0.0.1", port)
      ctx.ssl_version = "SSLv3"
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_nothing_raised do
        ssl.connect
      end
      ssl.puts("hello SSLv3")
      ssl.close
      sock.close
      #
      sock = TCPSocket.new("127.0.0.1", port)
      ctx.ssl_version = "SSLv3_server"
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError) do
        ssl.connect
      end
      sock.close
      #
      sock = TCPSocket.new("127.0.0.1", port)
      ctx.ssl_version = "TLSv1_client"
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_nothing_raised do
        ssl.connect
      end
      ssl.puts("hello TLSv1_client")
      ssl.close
      sock.close
    }
  end

  def test_sslctx_ssl_version
    args = {}
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.ssl_version = "TLSv1"
    }
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, args){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      ctx.ssl_version = "TLSv1"
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_nothing_raised do
        ssl.connect
      end
      ssl.puts("hello TLSv1")
      ssl.close
      sock.close
      #
      sock = TCPSocket.new("127.0.0.1", port)
      ctx.ssl_version = "SSLv3"
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError) do
        ssl.connect
      end
    }
  end

  def test_verify_depth
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    args = {}
    # depth == 1 => OK
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.cert = @svr_cert
      server_ctx.key = @svr_key
      server_ctx.verify_mode = vflag
      server_ctx.verify_depth = 1
    }
    start_server(PORT, vflag, true, args){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = @cli_key
      ctx.cert = @cli_cert
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_nothing_raised do
        ssl.connect
      end
      ssl.close
    }
    # depth == 0 => error
    error = nil
    args[:ctx_proc] = proc { |server_ctx|
      server_ctx.cert = @svr_cert
      server_ctx.key = @svr_key
      server_ctx.verify_mode = vflag
      server_ctx.verify_depth = 0
      server_ctx.verify_callback = proc { |preverify_ok, store_ctx|
        error = store_ctx.error
        preverify_ok
      }
    }
    start_server(PORT, vflag, true, args){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = @cli_key
      ctx.cert = @cli_cert
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raises(OpenSSL::SSL::SSLError) do
        ssl.connect
      end
      ssl.close
    }
    assert_equal OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY, error
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

  def test_sslctx_ciphers
    c = OpenSSL::SSL::SSLContext.new

    c.ciphers = 'DEFAULT'
    default = c.ciphers
    assert(default.size > 0)

    c.ciphers = 'ALL'
    all = c.ciphers
    assert(all.size > 0)

    c.ciphers = 'LOW'
    low = c.ciphers
    assert(low.size > 0)

    c.ciphers = 'MEDIUM'
    medium = c.ciphers
    assert(medium.size > 0)

    c.ciphers = 'HIGH'
    high = c.ciphers
    assert(high.size > 0)

    c.ciphers = 'EXP'
    exp = c.ciphers
    assert(exp.size > 0)

    # -
    c.ciphers = 'ALL:-LOW'
    assert_equal(all - low, c.ciphers)
    c.ciphers = 'ALL:-MEDIUM'
    assert_equal(all - medium, c.ciphers)
    c.ciphers = 'ALL:-HIGH'
    assert_equal(all - high, c.ciphers)
    c.ciphers = 'ALL:-EXP'
    assert_equal(all - exp, c.ciphers)
    c.ciphers = 'ALL:-LOW:-MEDIUM'
    assert_equal(all - low - medium, c.ciphers)
    c.ciphers = 'ALL:-LOW:-MEDIUM:-HIGH'
    assert_equal(all - low - medium - high, c.ciphers)
    assert_raise(OpenSSL::SSL::SSLError) do
      # should be empty for OpenSSL/0.9.8l. check OpenSSL changes if this test fail.
      c.ciphers = 'ALL:-LOW:-MEDIUM:-HIGH:-EXP'
    end

    # !
    c.ciphers = 'ALL:-LOW:LOW'
    assert_equal(all.sort, c.ciphers.sort)
    c.ciphers = 'ALL:!LOW:LOW'
    assert_equal(all - low, c.ciphers)
    c.ciphers = 'ALL:!LOW:+LOW'
    assert_equal(all - low, c.ciphers)

    # +
    c.ciphers = 'HIGH:LOW:+LOW'
    assert_equal(high + low, c.ciphers)
    c.ciphers = 'HIGH:LOW:+HIGH'
    assert_equal(low + high, c.ciphers)

    # name+name
    c.ciphers = 'RC4'
    rc4 = c.ciphers
    c.ciphers = 'RSA'
    rsa = c.ciphers
    c.ciphers = 'RC4+RSA'
    assert_equal(rc4&rsa, c.ciphers) 
    c.ciphers = 'RSA+RC4'
    assert_equal(rc4&rsa, c.ciphers) 
    c.ciphers = 'ALL:RSA+RC4'
    assert_equal(all + ((rc4&rsa) - all), c.ciphers) 
  end

  def test_sslctx_options
    args = {}
    args[:ctx_proc] = proc { |server_ctx|
      # TLSv1 only
      server_ctx.options = OpenSSL::SSL::OP_NO_SSLv2|OpenSSL::SSL::OP_NO_SSLv3
    }
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, args){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      ctx.options = OpenSSL::SSL::OP_NO_TLSv1
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_raise(OpenSSL::SSL::SSLError, Errno::ECONNRESET) do
        ssl.connect
      end
      ssl.close
      sock.close
      #
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      ctx.options = OpenSSL::SSL::OP_NO_SSLv3
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      assert_nothing_raised do
        ssl.connect
      end
      ssl.close
      sock.close
    }
  end

  def test_post_connection_check
    sslerr = OpenSSL::SSL::SSLError

    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.connect
      assert_raise(sslerr){ssl.post_connection_check("localhost.localdomain")}
      assert_raise(sslerr){ssl.post_connection_check("127.0.0.1")}
      assert(ssl.post_connection_check("localhost"))
      assert_raise(sslerr){ssl.post_connection_check("foo.example.com")}

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
      assert_raise(sslerr){ssl.post_connection_check("localhost")}
      assert_raise(sslerr){ssl.post_connection_check("foo.example.com")}

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
      assert_raise(sslerr){ssl.post_connection_check("127.0.0.1")}
      assert_raise(sslerr){ssl.post_connection_check("localhost")}
      assert_raise(sslerr){ssl.post_connection_check("foo.example.com")}
      cert = ssl.peer_cert
      assert(OpenSSL::SSL.verify_certificate_identity(cert, "localhost.localdomain"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "127.0.0.1"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "localhost"))
      assert(!OpenSSL::SSL.verify_certificate_identity(cert, "foo.example.com"))
    }
  end

  def test_client_session
    last_session = nil
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true) do |server, port|
      2.times do
        sock = TCPSocket.new("127.0.0.1", port)
        # Debian's openssl 0.9.8g-13 failed at assert(ssl.session_reused?),
        # when use default SSLContext. [ruby-dev:36167]
        ctx = OpenSSL::SSL::SSLContext.new("TLSv1")
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.sync_close = true
        ssl.session = last_session if last_session
        ssl.connect

        session = ssl.session
        if last_session
          assert(ssl.session_reused?)

          if session.respond_to?(:id)
            assert_equal(session.id, last_session.id)
          end
          assert_equal(session.to_pem, last_session.to_pem)
          assert_equal(session.to_der, last_session.to_der)
          # Older version of OpenSSL may not be consistent.  Look up which versions later.
          assert_equal(session.to_text, last_session.to_text)
        else
          assert(!ssl.session_reused?)
        end
        last_session = session

        str = "x" * 100 + "\n"
        ssl.puts(str)
        assert_equal(str, ssl.gets)

        ssl.close
      end
    end
  end

  def test_server_session
    connections = 0
    saved_session = nil

    ctx_proc = Proc.new do |ctx, ssl|
# add test for session callbacks here
    end

    server_proc = Proc.new do |ctx, ssl|
      session = ssl.session
      stats = ctx.session_cache_stats

      case connections
      when 0
        assert_equal(stats[:cache_num], 1)
        assert_equal(stats[:cache_hits], 0)
        assert_equal(stats[:cache_misses], 0)
        assert(!ssl.session_reused?)
      when 1
        assert_equal(stats[:cache_num], 1)
        assert_equal(stats[:cache_hits], 1)
        assert_equal(stats[:cache_misses], 0)
        assert(ssl.session_reused?)
        ctx.session_remove(session)
        saved_session = session
      when 2
        assert_equal(stats[:cache_num], 1)
        assert_equal(stats[:cache_hits], 1)
        assert_equal(stats[:cache_misses], 1)
        assert(!ssl.session_reused?)
        ctx.session_add(saved_session)
      when 3
        assert_equal(stats[:cache_num], 2)
        assert_equal(stats[:cache_hits], 2)
        assert_equal(stats[:cache_misses], 1)
        assert(ssl.session_reused?)
        ctx.flush_sessions(Time.now + 5000)
      when 4
        assert_equal(stats[:cache_num], 1)
        assert_equal(stats[:cache_hits], 2)
        assert_equal(stats[:cache_misses], 2)
        assert(!ssl.session_reused?)
        ctx.session_add(saved_session)
      end
      connections += 1

      readwrite_loop(ctx, ssl)
    end

    first_session = nil
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, :ctx_proc => ctx_proc, :server_proc => server_proc) do |server, port|
      10.times do |i|
        sock = TCPSocket.new("127.0.0.1", port)
        ctx = OpenSSL::SSL::SSLContext.new
        if defined?(OpenSSL::SSL::OP_NO_TICKET)
          # disable RFC4507 support
          ctx.options = OpenSSL::SSL::OP_NO_TICKET
        end
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.sync_close = true
        ssl.session = first_session if first_session
        ssl.connect

        session = ssl.session
        if first_session
          case i
          when 1; assert(ssl.session_reused?)
          when 2; assert(!ssl.session_reused?)
          when 3; assert(ssl.session_reused?)
          when 4; assert(!ssl.session_reused?)
          when 5..10; assert(ssl.session_reused?)
          end
        end
        first_session ||= session

        str = "x" * 100 + "\n"
        ssl.puts(str)
        assert_equal(str, ssl.gets)

        ssl.close
      end
    end
  end

  def test_tlsext_hostname
    return unless OpenSSL::SSL::SSLSocket.instance_methods.include?("hostname")

    ctx_proc = Proc.new do |ctx, ssl|
      foo_ctx = ctx.dup

      ctx.servername_cb = Proc.new do |ssl2, hostname|
        case hostname
        when 'foo.example.com'
          foo_ctx
        when 'bar.example.com'
          nil
        else
          raise "unknown hostname #{hostname.inspect}"
        end
      end
    end

    server_proc = Proc.new do |ctx, ssl|
      readwrite_loop(ctx, ssl)
    end

    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, :ctx_proc => ctx_proc, :server_proc => server_proc) do |server, port|
      2.times do |i|
        sock = TCPSocket.new("127.0.0.1", port)
        ctx = OpenSSL::SSL::SSLContext.new
        if defined?(OpenSSL::SSL::OP_NO_TICKET)
          # disable RFC4507 support
          ctx.options = OpenSSL::SSL::OP_NO_TICKET
        end
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.sync_close = true
        ssl.hostname = (i & 1 == 0) ? 'foo.example.com' : 'bar.example.com'
        ssl.connect

        str = "x" * 100 + "\n"
        ssl.puts(str)
        assert_equal(str, ssl.gets)

        ssl.close
      end
    end
  end
end

end
