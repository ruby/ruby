# frozen_string_literal: true
require_relative "utils"

if defined?(OpenSSL::SSL)

class OpenSSL::TestSSL < OpenSSL::SSLTestCase
  def test_bad_socket
    bad_socket = Struct.new(:sync).new
    assert_raise TypeError do
      socket = OpenSSL::SSL::SSLSocket.new bad_socket
      # if the socket is not a T_FILE, `connect` will segv because it tries
      # to get the underlying file descriptor but the API it calls assumes
      # the object type is T_FILE
      socket.connect
    end
  end

  def test_ctx_setup
    ctx = OpenSSL::SSL::SSLContext.new
    assert_equal true, ctx.setup
    assert_predicate ctx, :frozen?
    assert_equal nil, ctx.setup
  end

  def test_ctx_options
    ctx = OpenSSL::SSL::SSLContext.new

    ctx.options = 4
    assert_equal 4, ctx.options & 4
    if ctx.options != 4
      pend "SSL_CTX_set_options() seems to be modified by distributor"
    end

    # Unsetting options
    ctx.options = 0
    assert_equal(0, ctx.options)

    # Option constants
    all_ops = OpenSSL::SSL.constants
      .grep(/^OP_/)
      .map { |c| OpenSSL::SSL.const_get(c) }
    all_ops.each { |op| assert_operator(op, :>=, 0) }
    everything = all_ops.inject(&:|)
    assert_operator(everything, :>, 0)
    ctx.options = everything
    assert_equal(everything, ctx.options)

    # Backwards compatibility: nil means OP_ALL
    ctx.options = nil
    assert_equal OpenSSL::SSL::OP_ALL, ctx.options
  end

  def test_ctx_options_config
    omit "LibreSSL and AWS-LC do not support OPENSSL_CONF" if libressl? || aws_lc?

    Tempfile.create("openssl.cnf") { |f|
      f.puts(<<~EOF)
        openssl_conf = default_conf
        [default_conf]
        ssl_conf = ssl_sect
        [ssl_sect]
        system_default = ssl_default_sect
        [ssl_default_sect]
        Options = -SessionTicket
      EOF
      f.close

      assert_separately([{ "OPENSSL_CONF" => f.path }, "-ropenssl"], <<~"end;")
        ctx = OpenSSL::SSL::SSLContext.new
        assert_equal OpenSSL::SSL::OP_NO_TICKET, ctx.options & OpenSSL::SSL::OP_NO_TICKET
        ctx.set_params
        assert_equal OpenSSL::SSL::OP_NO_TICKET, ctx.options & OpenSSL::SSL::OP_NO_TICKET
      end;
    }
  end

  def test_ssl_with_server_cert
    sctx = OpenSSL::SSL::SSLContext.new
    sctx.cert = @svr_cert
    sctx.key = @svr_key
    sctx.extra_chain_cert = [@ca_cert]

    server_proc = proc do |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, sctx).accept
      assert_equal @svr_cert.to_der, ssl.cert.to_der
      assert_equal nil, ssl.peer_cert
      readwrite_loop(ssl)
    end
    start_server_proc(server_proc) { |port|
      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ctx = OpenSSL::SSL::SSLContext.new
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.connect
        assert_equal sock, ssl.io
        assert_equal nil, ssl.cert
        assert_equal @svr_cert.to_der, ssl.peer_cert.to_der
        assert_equal 2, ssl.peer_cert_chain.size
        assert_equal @svr_cert.to_der, ssl.peer_cert_chain[0].to_der
        assert_equal @ca_cert.to_der, ssl.peer_cert_chain[1].to_der

        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      ensure
        ssl&.close
        sock&.close
      end
    }
  end

  def test_connect_accept_nonblock_no_exception
    server_proc = proc do |sock|
      s2 = OpenSSL::SSL::SSLSocket.new(sock, make_server_context)
      accepted = s2.accept_nonblock(exception: false)
      assert_equal(:wait_readable, accepted)
      loop do
        rv = s2.accept_nonblock(exception: false)
        case rv
        when :wait_readable
          IO.select([s2], nil, nil, 1)
        when :wait_writable
          IO.select(nil, [s2], nil, 1)
        else
          assert_same(s2, rv)
          break
        end
      end
      assert_equal("abc\n", s2.gets)
      s2.puts("abc")
      s2.close
    end
    start_server_proc(server_proc) do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      s1 = OpenSSL::SSL::SSLSocket.new(sock)
      loop do
        rv = s1.connect_nonblock(exception: false)
        case rv
        when :wait_readable
          IO.select([s1], nil, nil, 1)
        when :wait_writable
          IO.select(nil, [s1], nil, 1)
        else
          assert_same(s1, rv)
          break
        end
      end
      s1.puts("abc")
      assert_equal("abc\n", s1.gets)
    ensure
      sock&.close
    end
  end

  def test_connect_accept_nonblock
    server_proc = proc do |sock|
      s2 = OpenSSL::SSL::SSLSocket.new(sock, make_server_context)
      rv = 5.times {
        begin
          break s2.accept_nonblock
        rescue IO::WaitReadable
          IO.select([s2], nil, nil, 1)
        rescue IO::WaitWritable
          IO.select(nil, [s2], nil, 1)
        end
      }
      assert_same(s2, rv)
      assert_equal("a\n", s2.gets)
      s2.puts("b")
    end
    start_server_proc(server_proc) do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      s1 = OpenSSL::SSL::SSLSocket.new(sock)
      rv = 5.times {
        begin
          break s1.connect_nonblock
        rescue IO::WaitReadable
          IO.select([s1], nil, nil, 1)
        rescue IO::WaitWritable
          IO.select(nil, [s1], nil, 1)
        end
      }
      assert_same(s1, rv)
      s1.print "a\ndef"
      assert_equal("b\n", s1.gets)
    ensure
      sock&.close
    end
  end

  def test_low_level_socket
    start_server do |port|
      sock = Socket.tcp("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.connect
      ssl.puts("abc")
      assert_equal("abc\n", ssl.gets)
    ensure
      ssl&.close
      sock&.close
    end
  end

  def test_socket_open
    start_server { |port|
      begin
        ssl = OpenSSL::SSL::SSLSocket.open("127.0.0.1", port)
        ssl.sync_close = true
        ssl.connect

        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      ensure
        ssl&.close
      end
    }
  end

  def test_socket_open_with_context
    start_server { |port|
      begin
        ctx = OpenSSL::SSL::SSLContext.new
        ssl = OpenSSL::SSL::SSLSocket.open("127.0.0.1", port, context: ctx)
        ssl.sync_close = true
        ssl.connect

        assert_equal ssl.context, ctx
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      ensure
        ssl&.close
      end
    }
  end

  def test_socket_open_with_local_address_port_context
    start_server { |port|
      begin
        # Guess a free port number
        random_port = rand(49152..65535)
        ctx = OpenSSL::SSL::SSLContext.new
        ssl = OpenSSL::SSL::SSLSocket.open("127.0.0.1", port, "127.0.0.1", random_port, context: ctx)
        ssl.sync_close = true
        ssl.connect

        assert_equal ctx, ssl.context
        assert_equal random_port, ssl.io.local_address.ip_port
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      rescue Errno::EADDRINUSE, Errno::EACCES
      ensure
        ssl&.close
      end
    }
  end

  def test_add_certificate
    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(@svr_cert, @svr_key, [@ca_cert]) # RSA

    start_server(sctx) do |port|
      server_connect(port) { |ssl|
        assert_equal @svr_cert.subject, ssl.peer_cert.subject
        assert_equal [@svr_cert.subject, @ca_cert.subject],
          ssl.peer_cert_chain.map(&:subject)

        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }
    end
  end

  def test_add_certificate_multiple_certs
    ca2_key = Fixtures.pkey("rsa-3")
    ca2_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign, keyCertSign", true],
    ]
    ca2_dn = OpenSSL::X509::Name.parse_rfc2253("CN=CA2")
    ca2_cert = issue_cert(ca2_dn, ca2_key, 123, ca2_exts, nil, nil)

    ecdsa_key = Fixtures.pkey("p256")
    exts = [
      ["keyUsage", "digitalSignature", false],
    ]
    ecdsa_dn = OpenSSL::X509::Name.parse_rfc2253("CN=localhost2")
    ecdsa_cert = issue_cert(ecdsa_dn, ecdsa_key, 456, exts, ca2_cert, ca2_key)

    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(@svr_cert, @svr_key, [@ca_cert]) # RSA
    sctx.add_certificate(ecdsa_cert, ecdsa_key, [ca2_cert])

    start_server(sctx) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.max_version = :TLS1_2 # TODO: We need this to force certificate type
      ctx.ciphers = "aECDSA"
      server_connect(port, ctx) { |ssl|
        assert_equal ecdsa_cert.subject, ssl.peer_cert.subject
        assert_equal [ecdsa_cert.subject, ca2_cert.subject],
          ssl.peer_cert_chain.map(&:subject)
      }

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.max_version = :TLS1_2
      ctx.ciphers = "aRSA"
      server_connect(port, ctx) { |ssl|
        assert_equal @svr_cert.subject, ssl.peer_cert.subject
        assert_equal [@svr_cert.subject, @ca_cert.subject],
          ssl.peer_cert_chain.map(&:subject)
      }
    end
  end

  def test_extra_chain_cert_auto_chain
    start_server { |port|
      server_connect(port) { |ssl|
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        assert_equal @svr_cert.to_der, ssl.peer_cert.to_der
        assert_equal [@svr_cert], ssl.peer_cert_chain
      }
    }

    # AWS-LC enables SSL_MODE_NO_AUTO_CHAIN by default
    unless aws_lc?
      sctx = OpenSSL::SSL::SSLContext.new
      sctx.add_certificate(@svr_cert, @svr_key) # no extra certs
      sctx.cert_store = OpenSSL::X509::Store.new.tap { |store|
        store.add_cert(@ca_cert)
      }
      start_server(sctx) { |port|
        server_connect(port) { |ssl|
          ssl.puts "abc"; assert_equal "abc\n", ssl.gets
          assert_equal @svr_cert.to_der, ssl.peer_cert.to_der
          assert_equal [@svr_cert, @ca_cert], ssl.peer_cert_chain
        }
      }
    end
  end

  def test_read_with_timeout
    omit "does not support timeout" unless IO.method_defined?(:timeout)

    start_server do |port|
      server_connect(port) do |ssl|
        str = +("x" * 100 + "\n")
        ssl.syswrite(str)
        assert_equal(str, ssl.sysread(str.bytesize))

        ssl.timeout = 0.1
        assert_raise(IO::TimeoutError) { ssl.sysread(1) }

        ssl.syswrite(str)
        assert_equal(str, ssl.sysread(str.bytesize))

        buf = "orig".b
        assert_raise(IO::TimeoutError) { ssl.sysread(1, buf) }
        assert_equal("orig", buf)
        assert_nothing_raised { buf.clear }
      end
    end
  end

  def test_partial_tls_record_read_nonblock
    written = Thread::Queue.new
    read = Thread::Queue.new
    server_proc = proc do |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, make_server_context).accept
      str = ssl.gets
      ssl.puts(str)

      # the beginning of a TLS record
      ssl.io.write("\x17")
      written << :written
      read.pop
    end
    start_server_proc(server_proc) do |port|
      server_connect(port) do |ssl|
        ssl.puts("abc")
        assert_equal("abc\n", ssl.gets)
        written.pop
        # should raise a IO::WaitReadable since a full TLS record is not available
        # for reading
        assert_raise(IO::WaitReadable) { ssl.send(:sysread_nonblock, 1) }
        read << :done
      end
    end
  end

  def test_sync_close
    start_server do |port|
      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.connect
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        ssl.close
        assert_not_predicate sock, :closed?
      ensure
        sock&.close
      end

      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.sync_close = true  # !!
        ssl.connect
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        ssl.close
        assert_predicate sock, :closed?
      ensure
        sock&.close
      end
    end
  end

  def test_sync_close_initialize_opt
    start_server do |port|
      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock, sync_close: true)
        assert_equal true, ssl.sync_close
        ssl.connect
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        ssl.close
        assert_predicate sock, :closed?
      ensure
        sock&.close
      end
    end
  end

  def test_verify_mode_default
    ctx = OpenSSL::SSL::SSLContext.new
    assert_equal OpenSSL::SSL::VERIFY_NONE, ctx.verify_mode
  end

  def test_verify_mode_server_cert
    start_server(ignore_listener_error: true) { |port|
      populated_store = OpenSSL::X509::Store.new
      populated_store.add_cert(@ca_cert)
      empty_store = OpenSSL::X509::Store.new

      # Valid certificate, SSL_VERIFY_PEER
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.cert_store = populated_store
      assert_nothing_raised {
        server_connect(port, ctx) { |ssl| ssl.puts("abc"); ssl.gets }
      }

      # Invalid certificate, SSL_VERIFY_NONE
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      ctx.cert_store = empty_store
      assert_nothing_raised {
        server_connect(port, ctx) { |ssl| ssl.puts("abc"); ssl.gets }
      }

      # Invalid certificate, SSL_VERIFY_PEER
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.cert_store = empty_store
      assert_raise(OpenSSL::SSL::SSLError) {
        server_connect(port, ctx)
      }
    }
  end

  def test_verify_mode_client_cert_required
    # Optional, client certificate not supplied
    sctx = make_server_context
    sctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    server_proc = proc do |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, sctx).accept
      assert_equal nil, ssl.peer_cert
      readwrite_loop(ssl)
    end
    start_server_proc(server_proc) { |port|
      assert_nothing_raised {
        server_connect(port) { |ssl| ssl.puts("abc"); ssl.gets }
      }
    }

    # Required, client certificate not supplied
    sctx = make_server_context
    sctx.verify_mode =
      OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(sctx, ignore_listener_error: true) { |port|
      # TLS 1.3 alert: certificate_required(116)
      assert_raise_with_message(OpenSSL::SSL::SSLError, /alert number 116/) {
        server_connect(port) { |ssl| ssl.puts("abc"); ssl.gets }
      }
    }
  end

  def test_client_auth_success
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    store.purpose = OpenSSL::X509::PURPOSE_SSL_CLIENT

    sctx = make_server_context
    sctx.verify_mode =
      OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    sctx.cert_store = store
    # LibreSSL doesn't support client_cert_cb in TLS 1.3
    sctx.max_version = OpenSSL::SSL::TLS1_2_VERSION if libressl?

    start_server(sctx) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.key = @cli_key
      ctx.cert = @cli_cert

      server_connect(port, ctx) { |ssl|
        ssl.puts("foo")
        assert_equal("foo\n", ssl.gets)
      }

      called = nil
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.client_cert_cb = Proc.new{ |sslconn|
        called = true
        [@cli_cert, @cli_key]
      }

      server_connect(port, ctx) { |ssl|
        assert(called)
        ssl.puts("foo")
        assert_equal("foo\n", ssl.gets)
      }
    }
  end

  def test_client_cert_cb_ignore_error
    sctx = make_server_context
    sctx.verify_mode =
      OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT

    start_server(sctx, ignore_listener_error: true) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.client_cert_cb = -> ssl {
        raise "exception in client_cert_cb must be suppressed"
      }
      # 1. Exception in client_cert_cb is suppressed
      # 2. No client certificate will be sent to the server
      # 3. SSL_VERIFY_FAIL_IF_NO_PEER_CERT causes the handshake to fail
      assert_raise(OpenSSL::SSL::SSLError) {
        server_connect(port, ctx) { |ssl| ssl.puts("abc"); ssl.gets }
      }
    end
  end

  def test_client_ca
    pend "LibreSSL doesn't support certificate_authorities" if libressl?

    sctx = make_server_context
    sctx.verify_mode =
      OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    store.purpose = OpenSSL::X509::PURPOSE_SSL_CLIENT
    sctx.cert_store = store
    sctx.client_ca = [@ca_cert]

    start_server(sctx) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      client_ca_from_server = nil
      ctx.client_cert_cb = Proc.new do |sslconn|
        client_ca_from_server = sslconn.client_ca
        [@cli_cert, @cli_key]
      end
      server_connect(port, ctx) { |ssl|
        assert_equal([@ca], client_ca_from_server)
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }
    }
  end

  def test_unstarted_session
    start_server do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)

      assert_raise(OpenSSL::SSL::SSLError) { ssl.syswrite("data") }
      assert_raise(OpenSSL::SSL::SSLError) { ssl.sysread(1) }

      ssl.connect
      ssl.puts "abc"
      assert_equal "abc\n", ssl.gets
    ensure
      ssl&.close
      sock&.close
    end
  end

  def test_parallel
    start_server { |port|
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
    start_server(ignore_listener_error: true) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
        assert_equal(OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY, ssl.verify_result)
      ensure
        ssl.close
      end
    }

    start_server { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.verify_callback = Proc.new do |preverify_ok, store_ctx|
        store_ctx.error = OpenSSL::X509::V_OK
        true
      end
      server_connect(port, ctx) { |ssl|
        assert_equal(OpenSSL::X509::V_OK, ssl.verify_result)
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }
    }

    start_server(ignore_listener_error: true) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.verify_callback = Proc.new do |preverify_ok, store_ctx|
        store_ctx.error = OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION
        false
      end
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
        assert_equal(OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION, ssl.verify_result)
      ensure
        ssl.close
      end
    }
  end

  def test_exception_in_verify_callback_is_ignored
    start_server(ignore_listener_error: true) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.verify_callback = Proc.new do |preverify_ok, store_ctx|
        store_ctx.error = OpenSSL::X509::V_OK
        raise RuntimeError
      end
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        EnvUtil.suppress_warning do
          # SSLError, not RuntimeError
          assert_raise(OpenSSL::SSL::SSLError) { ssl.connect }
        end
        assert_equal(OpenSSL::X509::V_ERR_CERT_REJECTED, ssl.verify_result)
      ensure
        ssl.close
      end
    }
  end

  def test_ca_file
    start_server(ignore_listener_error: true) { |port|
      # X509_STORE is shared; setting ca_file to SSLContext affects store
      store = OpenSSL::X509::Store.new
      assert_equal false, store.verify(@svr_cert)

      ctx = Tempfile.create("ca_cert.pem") { |f|
        f.puts(@ca_cert.to_pem)
        f.close

        ctx = OpenSSL::SSL::SSLContext.new
        ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
        ctx.cert_store = store
        ctx.ca_file = f.path
        ctx.setup
        ctx
      }
      assert_nothing_raised {
        server_connect(port, ctx) { |ssl| ssl.puts("abc"); ssl.gets }
      }
      assert_equal true, store.verify(@svr_cert)
    }
  end

  def test_ca_file_not_found
    path = Tempfile.create("ca_cert.pem") { |f| f.path }
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.ca_file = path
    # OpenSSL >= 1.1.0: /no certificate or crl found/
    assert_raise(OpenSSL::SSL::SSLError) {
      ctx.setup
    }
  end

  def test_finished_messages
    server_finished = nil
    server_peer_finished = nil
    client_finished = nil
    client_peer_finished = nil

    server_proc = proc do |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, make_server_context).accept
      server_finished = ssl.finished_message
      server_peer_finished = ssl.peer_finished_message
      readwrite_loop(ssl)
    end
    start_server_proc(server_proc) { |port|
      server_connect(port) { |ssl|
        ssl.puts "abc"; ssl.gets

        client_finished = ssl.finished_message
        client_peer_finished = ssl.peer_finished_message
      }
    }
    assert_not_nil(server_finished)
    assert_not_nil(client_finished)
    assert_equal(server_finished, client_peer_finished)
    assert_equal(server_peer_finished, client_finished)
  end

  def test_sslctx_set_params
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.set_params

    assert_equal OpenSSL::SSL::VERIFY_PEER, ctx.verify_mode
    ciphers_names = ctx.ciphers.collect{|v, _, _, _| v }
    assert ciphers_names.all?{|v| /A(EC)?DH/ !~ v }, "anon ciphers are disabled"
    assert ciphers_names.all?{|v| /(RC4|MD5|EXP|DES(?!-EDE|-CBC3))/ !~ v }, "weak ciphers are disabled"
    assert_equal 0, ctx.options & OpenSSL::SSL::OP_DONT_INSERT_EMPTY_FRAGMENTS
    assert_equal OpenSSL::SSL::OP_NO_COMPRESSION,
                 ctx.options & OpenSSL::SSL::OP_NO_COMPRESSION
  end

  def test_post_connect_check_with_anon_ciphers
    # DH missing the q value on unknown named parameters is not FIPS-approved.
    omit_on_fips
    omit "AWS-LC does not support DHE ciphersuites" if aws_lc?

    sctx = OpenSSL::SSL::SSLContext.new
    sctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
    sctx.ciphers = "aNULL"
    sctx.tmp_dh = Fixtures.pkey("dh-1")
    sctx.security_level = 0

    start_server(sctx) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
      ctx.ciphers = "aNULL"
      ctx.security_level = 0
      server_connect(port, ctx) { |ssl|
        assert_raise_with_message(OpenSSL::SSL::SSLError, /anonymous cipher suite/i) {
          ssl.post_connection_check("localhost.localdomain")
        }
      }
    }
  end

  def test_post_connection_check
    sslerr = OpenSSL::SSL::SSLError

    start_server { |port|
      server_connect(port) { |ssl|
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets

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
    }

    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:localhost.localdomain,IP:127.0.0.1",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 4, exts, @ca_cert, @ca_key)
    start_server { |port|
      server_connect(port) { |ssl|
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets

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
    }

    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:*.localdomain",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 5, exts, @ca_cert, @ca_key)
    start_server { |port|
      server_connect(port) { |ssl|
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets

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
    }
  end

  def test_verify_certificate_identity
    [true, false].each do |criticality|
      cert = create_null_byte_SAN_certificate(criticality)
      assert_equal(false, OpenSSL::SSL.verify_certificate_identity(cert, 'www.example.com'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, "www.example.com\0.evil.com"))
      assert_equal(false, OpenSSL::SSL.verify_certificate_identity(cert, '192.168.7.255'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, '192.168.7.1'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, '13::17'))
      assert_equal(false,  OpenSSL::SSL.verify_certificate_identity(cert, '13::18'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, '13:0:0:0:0:0:0:17'))
      assert_equal(false,  OpenSSL::SSL.verify_certificate_identity(cert, '44:0:0:0:0:0:0:17'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, '0013:0000:0000:0000:0000:0000:0000:0017'))
      assert_equal(false,  OpenSSL::SSL.verify_certificate_identity(cert, '1313:0000:0000:0000:0000:0000:0000:0017'))
    end
  end

  def test_verify_hostname
    assert_equal(true,  OpenSSL::SSL.verify_hostname("www.example.com", "*.example.com"))
    assert_equal(false, OpenSSL::SSL.verify_hostname("www.subdomain.example.com", "*.example.com"))
  end

  def test_verify_wildcard
    assert_equal(false, OpenSSL::SSL.verify_wildcard("foo", "x*"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("foo", "foo"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("foo", "f*"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("foo", "*"))
    assert_equal(false, OpenSSL::SSL.verify_wildcard("abc*bcd", "abcd"))
    assert_equal(false, OpenSSL::SSL.verify_wildcard("xn--qdk4b9b", "x*"))
    assert_equal(false, OpenSSL::SSL.verify_wildcard("xn--qdk4b9b", "*--qdk4b9b"))
    assert_equal(true,  OpenSSL::SSL.verify_wildcard("xn--qdk4b9b", "xn--qdk4b9b"))
  end

  # Comments in this test is excerpted from https://www.rfc-editor.org/rfc/rfc6125#page-27
  def test_post_connection_check_wildcard_san
    # case-insensitive ASCII comparison
    # RFC 6125, section 6.4.1
    #
    # "..matching of the reference identifier against the presented identifier
    # is performed by comparing the set of domain name labels using a
    # case-insensitive ASCII comparison, as clarified by [DNS-CASE] (e.g.,
    # "WWW.Example.Com" would be lower-cased to "www.example.com" for
    # comparison purposes)
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.Example.COM'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'WWW.Example.COM'))
    # 1.  The client SHOULD NOT attempt to match a presented identifier in
    #     which the wildcard character comprises a label other than the
    #     left-most label (e.g., do not match bar.*.example.net).
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:www.*.com'), 'www.example.com'))
    # 2.  If the wildcard character is the only character of the left-most
    #     label in the presented identifier, the client SHOULD NOT compare
    #     against anything but the left-most label of the reference
    #     identifier (e.g., *.example.com would match foo.example.com but
    #     not bar.foo.example.com or example.com).
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'foo.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*.example.com'), 'bar.foo.example.com'))
    # 3.  The client MAY match a presented identifier in which the wildcard
    #     character is not the only character of the label (e.g.,
    #     baz*.example.net and *baz.example.net and b*z.example.net would
    #     be taken to match baz1.example.net and foobaz.example.net and
    #     buzz.example.net, respectively).  ...
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:baz*.example.com'), 'baz1.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*baz.example.com'), 'foobaz.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:b*z.example.com'), 'buzz.example.com'))

    # Section 6.4.3 of RFC6125 states that client should NOT match identifier
    # where wildcard is other than left-most label.
    #
    # Also implicitly mentions the wildcard character only in singular form,
    # and discourages matching against more than one wildcard.
    #
    # See RFC 6125, section 7.2, subitem 2.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*b*.example.com'), 'abc.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*b*.example.com'), 'ab.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:*b*.example.com'), 'bc.example.com'))
    #                                ...  However, the client SHOULD NOT
    #   attempt to match a presented identifier where the wildcard
    #   character is embedded within an A-label or U-label [IDNA-DEFS] of
    #   an internationalized domain name [IDNA-PROTO].
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:xn*.example.com'), 'xn1ca.example.com'))
    # part of A-label
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:xn--*.example.com'), 'xn--1ca.example.com'))
    # part of U-label
    # dNSName in RFC5280 is an IA5String so U-label should NOT be allowed
    # regardless of wildcard.
    #
    # See Section 7.2 of RFC 5280:
    #   IA5String is limited to the set of ASCII characters.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_san('DNS:á*.example.com'), 'á1.example.com'))
  end

  def test_post_connection_check_wildcard_cn
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.Example.COM'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'WWW.Example.COM'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('www.*.com'), 'www.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'foo.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*.example.com'), 'bar.foo.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('baz*.example.com'), 'baz1.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*baz.example.com'), 'foobaz.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('b*z.example.com'), 'buzz.example.com'))
    # Section 6.4.3 of RFC6125 states that client should NOT match identifier
    # where wildcard is other than left-most label.
    #
    # Also implicitly mentions the wildcard character only in singular form,
    # and discourages matching against more than one wildcard.
    #
    # See RFC 6125, section 7.2, subitem 2.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*b*.example.com'), 'abc.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*b*.example.com'), 'ab.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('*b*.example.com'), 'bc.example.com'))
    assert_equal(true, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('xn*.example.com'), 'xn1ca.example.com'))
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('xn--*.example.com'), 'xn--1ca.example.com'))
    # part of U-label
    # Subject in RFC5280 states case-insensitive ASCII comparison.
    #
    # See Section 7.2 of RFC 5280:
    #   IA5String is limited to the set of ASCII characters.
    assert_equal(false, OpenSSL::SSL.verify_certificate_identity(
      create_cert_with_name('á*.example.com'), 'á1.example.com'))
  end

  def create_cert_with_san(san)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse("/DC=some/DC=site/CN=Some Site")
    v = OpenSSL::ASN1::Sequence(san.split(",").map { |item|
      type, value = item.split(":", 2)
      case type
      when "DNS" then OpenSSL::ASN1::IA5String(value, 2, :IMPLICIT)
      when "IP" then OpenSSL::ASN1::OctetString(IPAddr.new(value).hton, 7, :IMPLICIT)
      else raise "unsupported"
      end
    })
    cert.add_extension(OpenSSL::X509::Extension.new("subjectAltName", v))
    cert
  end

  def create_cert_with_name(name)
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.new([['DC', 'some'], ['DC', 'site'], ['CN', name]])
    cert
  end


  # Create NULL byte SAN certificate
  def create_null_byte_SAN_certificate(critical = false)
    ef = OpenSSL::X509::ExtensionFactory.new
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse "/DC=some/DC=site/CN=Some Site"
    ext = ef.create_ext('subjectAltName', 'DNS:placeholder,IP:192.168.7.1,IP:13::17', critical)
    ext_asn1 = OpenSSL::ASN1.decode(ext.to_der)
    san_list_der = ext_asn1.value.reduce(nil) { |memo,val| val.tag == 4 ? val.value : memo }
    san_list_asn1 = OpenSSL::ASN1.decode(san_list_der)
    san_list_asn1.value[0].value = "www.example.com\0.evil.com"
    pos = critical ? 2 : 1
    ext_asn1.value[pos].value = san_list_asn1.to_der
    real_ext = OpenSSL::X509::Extension.new ext_asn1
    cert.add_extension(real_ext)
    cert
  end

  def test_keylog_cb
    omit "Keylog callback is not supported" if libressl?

    prefix = 'CLIENT_RANDOM'
    context = OpenSSL::SSL::SSLContext.new
    context.min_version = context.max_version = OpenSSL::SSL::TLS1_2_VERSION

    cb_called = false
    context.keylog_cb = proc do |_sock, line|
      cb_called = true
      assert_equal(prefix, line.split.first)
    end

    start_server do |port|
      server_connect(port, context) do |ssl|
        ssl.puts "abc"
        assert_equal("abc\n", ssl.gets)
        assert_equal(true, cb_called)
      end
    end

    prefixes = [
      'SERVER_HANDSHAKE_TRAFFIC_SECRET',
      'EXPORTER_SECRET',
      'SERVER_TRAFFIC_SECRET_0',
      'CLIENT_HANDSHAKE_TRAFFIC_SECRET',
      'CLIENT_TRAFFIC_SECRET_0',
    ]
    context = OpenSSL::SSL::SSLContext.new
    context.min_version = context.max_version = OpenSSL::SSL::TLS1_3_VERSION
    cb_called = false
    context.keylog_cb = proc do |_sock, line|
      cb_called = true
      assert_not_nil(prefixes.delete(line.split.first))
    end

    start_server do |port|
      server_connect(port, context) do |ssl|
        ssl.puts "abc"
        assert_equal("abc\n", ssl.gets)
        assert_equal(true, cb_called)
      end
      assert_equal(0, prefixes.size)
    end
  end

  def test_tlsext_hostname
    fooctx = OpenSSL::SSL::SSLContext.new
    fooctx.cert = @cli_cert
    fooctx.key = @cli_key

    sctx = make_server_context
    sctx.servername_cb = proc { |ssl, servername|
      case servername
      when "foo.example.com"
        fooctx
      when "bar.example.com"
        nil
      else
        raise "unreachable"
      end
    }
    start_server(sctx) do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      begin
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.hostname = "foo.example.com"
        ssl.connect
        assert_equal @cli_cert.serial, ssl.peer_cert.serial
        assert_predicate fooctx, :frozen?

        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      ensure
        ssl&.close
        sock.close
      end

      sock = TCPSocket.new("127.0.0.1", port)
      begin
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.hostname = "bar.example.com"
        ssl.connect
        assert_equal @svr_cert.serial, ssl.peer_cert.serial

        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      ensure
        ssl&.close
        sock.close
      end
    end
  end

  def test_servername_cb_exception
    server_proc = proc do |sock|
      sctx = make_server_context
      sctx.servername_cb = lambda { |args| raise RuntimeError, "foo" }
      ssl = OpenSSL::SSL::SSLSocket.new(sock, sctx)
      assert_raise_with_message(RuntimeError, "foo") { ssl.accept }
    end
    start_server_proc(server_proc) do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.hostname = "example.org"
      assert_raise_with_message(OpenSSL::SSL::SSLError, /unrecognized.name/i) {
        ssl.connect
      }
    ensure
      sock&.close
    end
  end

  def test_servername_cb_raises_an_exception_on_unknown_objects
    server_proc = proc do |sock|
      sctx = make_server_context
      sctx.servername_cb = lambda { |args| Object.new }
      ssl = OpenSSL::SSL::SSLSocket.new(sock, sctx)
      assert_raise(ArgumentError) { ssl.accept }
    end
    start_server_proc(server_proc) do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.hostname = "example.org"
      assert_raise_with_message(OpenSSL::SSL::SSLError, /unrecognized.name/i) {
        ssl.connect
      }
    ensure
      sock&.close
    end
  end

  def test_verify_hostname_on_connect
    exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
      ["subjectAltName", "DNS:a.example.com,DNS:*.b.example.com," \
                         "DNS:c*.example.com,DNS:d.*.example.com"],
    ]
    cert = issue_cert(@svr, @svr_key, 4, exts, @ca_cert, @ca_key)
    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(cert, @svr_key)

    start_server(sctx, ignore_listener_error: true) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      assert_equal false, ctx.verify_hostname
      ctx.verify_hostname = true
      ctx.cert_store = OpenSSL::X509::Store.new
      ctx.cert_store.add_cert(@ca_cert)
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER

      [
        ["a.example.com", true],
        ["A.Example.Com", true],
        ["x.example.com", false],
        ["b.example.com", false],
        ["x.b.example.com", true],
        ["cx.example.com", true],
        ["d.x.example.com", false],
      ].each do |name, expected_ok|
        begin
          sock = TCPSocket.new("127.0.0.1", port)
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.hostname = name
          if expected_ok
            ssl.connect
            ssl.puts "abc"; assert_equal "abc\n", ssl.gets
          else
            assert_raise(OpenSSL::SSL::SSLError) { ssl.connect }
          end
        ensure
          ssl.close if ssl
          sock.close if sock
        end
      end
    end
  end

  def test_verify_hostname_failure_error_code
    exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
      ["subjectAltName", "DNS:a.example.com"],
    ]
    cert = issue_cert(@svr, @svr_key, 4, exts, @ca_cert, @ca_key)
    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(cert, @svr_key)

    start_server(sctx, ignore_listener_error: true) do |port|
      verify_callback_ok = verify_callback_err = nil

      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_hostname = true
      ctx.cert_store = OpenSSL::X509::Store.new
      ctx.cert_store.add_cert(@ca_cert)
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.verify_callback = -> (preverify_ok, store_ctx) {
        verify_callback_ok = preverify_ok
        verify_callback_err = store_ctx.error
        preverify_ok
      }

      begin
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.hostname = "b.example.com"
        assert_raise(OpenSSL::SSL::SSLError) { ssl.connect }
        assert_equal false, verify_callback_ok
        assert_equal OpenSSL::X509::V_ERR_HOSTNAME_MISMATCH, verify_callback_err
      ensure
        sock&.close
      end
    end
  end

  def test_connect_systemcallerror
    # SSL_connect() should fail with SSL_ERROR_SYSCALL and errno should be
    # kept intact from the underlying recv(2)/send(2).
    pend "AWS-LC does not preserve errno on SSL_ERROR_SYSCALL" if aws_lc?

    server_proc = proc do |sock|
      sock.setsockopt(:SOCKET, :LINGER, [1, 0].pack("ii"))
      sock.read(1)
      sock.close
    end
    start_server_proc(server_proc) do |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      assert_raise(Errno::ECONNRESET, Errno::EPIPE) {
        ssl.connect
      }
    ensure
      sock&.close
    end
  end

  def test_connect_certificate_verify_failed_exception_message
    start_server(ignore_listener_error: true) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      assert_raise_with_message(OpenSSL::SSL::SSLError, /unable to get local issuer certificate/) {
        server_connect(port, ctx)
      }
    }

    now = Time.now
    cert = issue_cert(@svr, @svr_key, 30, [], @ca_cert, @ca_key,
                      not_before: now - 7200, not_after: now - 3600)
    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(cert, @svr_key)

    start_server(sctx, ignore_listener_error: true) { |port|
      store = OpenSSL::X509::Store.new
      store.add_cert(@ca_cert)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(cert_store: store)
      assert_raise_with_message(OpenSSL::SSL::SSLError, /expired/) {
        server_connect(port, ctx)
      }
    }
  end

  def test_connect_exception_message_include_peeraddr
    start_server(ignore_listener_error: true) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      assert_raise_with_message(OpenSSL::SSL::SSLError, /peeraddr=127\.0\.0\.1/) do
        server_connect(port, ctx) { }
      end
    end
  end

  def check_supported_protocol_versions
    possible_versions = [
      OpenSSL::SSL::SSL3_VERSION,
      OpenSSL::SSL::TLS1_VERSION,
      OpenSSL::SSL::TLS1_1_VERSION,
      OpenSSL::SSL::TLS1_2_VERSION,
      OpenSSL::SSL::TLS1_3_VERSION,
    ]
    supported = []

    sctx = make_server_context
    # The default security level is 1 in OpenSSL <= 3.1, 2 in OpenSSL >= 3.2
    # In OpenSSL >= 3.0, TLS 1.1 or older is disabled at level 1
    sctx.security_level = 0
    # Explicitly reset them to avoid influenced by OPENSSL_CONF
    sctx.min_version = sctx.max_version = nil

    start_server(sctx, ignore_listener_error: true) do |port|
      possible_versions.each do |ver|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.security_level = 0
        ctx.min_version = ctx.max_version = ver
        server_connect(port, ctx) { |ssl|
          ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        }
        supported << ver
      rescue OpenSSL::SSL::SSLError
      end
    end

    # Sanity check: in our test suite we assume these are always supported
    assert_include(supported, OpenSSL::SSL::TLS1_2_VERSION)
    assert_include(supported, OpenSSL::SSL::TLS1_3_VERSION)

    supported
  end

  def test_set_params_min_version
    supported = check_supported_protocol_versions
    return unless supported.include?(OpenSSL::SSL::SSL3_VERSION)

    # SSLContext#set_params properly disables SSL 3.0 by default
    sctx = make_server_context
    sctx.min_version = sctx.max_version = OpenSSL::SSL::SSL3_VERSION

    start_server(sctx, ignore_listener_error: true) { |port|
      store = OpenSSL::X509::Store.new
      store.add_cert(@ca_cert)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(cert_store: store, verify_hostname: false)
      assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx) }
    }
  end

  def test_minmax_version
    supported = check_supported_protocol_versions

    # name: The string that would be returned by SSL_get_version()
    # method: The version-specific method name (if any)
    vmap = {
      OpenSSL::SSL::SSL3_VERSION => { name: "SSLv3", method: "SSLv3" },
      OpenSSL::SSL::SSL3_VERSION => { name: "SSLv3", method: "SSLv3" },
      OpenSSL::SSL::TLS1_VERSION => { name: "TLSv1", method: "TLSv1" },
      OpenSSL::SSL::TLS1_1_VERSION => { name: "TLSv1.1", method: "TLSv1_1" },
      OpenSSL::SSL::TLS1_2_VERSION => { name: "TLSv1.2", method: "TLSv1_2" },
      OpenSSL::SSL::TLS1_3_VERSION => { name: "TLSv1.3", method: nil },
    }

    # Server enables a single version
    supported.each do |ver|
      sctx = make_server_context
      sctx.security_level = 0
      sctx.min_version = sctx.max_version = ver

      start_server(sctx, ignore_listener_error: true) { |port|
        supported.each do |cver|
          # Client enables a single version
          ctx1 = OpenSSL::SSL::SSLContext.new
          ctx1.security_level = 0
          ctx1.min_version = ctx1.max_version = cver
          if ver == cver
            server_connect(port, ctx1) { |ssl|
              assert_equal vmap[cver][:name], ssl.ssl_version
              ssl.puts "abc"; assert_equal "abc\n", ssl.gets
            }
          else
            assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx1) }
          end

          # There is no version-specific SSL methods for TLS 1.3
          if cver <= OpenSSL::SSL::TLS1_2_VERSION
            # Client enables a single version using #ssl_version=
            ctx2 = OpenSSL::SSL::SSLContext.new
            ctx2.security_level = 0
            ctx2.ssl_version = vmap[cver][:method]
            if ver == cver
              server_connect(port, ctx2) { |ssl|
                assert_equal vmap[cver][:name], ssl.ssl_version
                ssl.puts "abc"; assert_equal "abc\n", ssl.gets
              }
            else
              assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx2) }
            end
          end
        end

        # Client enables all supported versions
        ctx3 = OpenSSL::SSL::SSLContext.new
        ctx3.security_level = 0
        ctx3.min_version = ctx3.max_version = nil
        server_connect(port, ctx3) { |ssl|
          assert_equal vmap[ver][:name], ssl.ssl_version
          ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        }
      }
    end

    if supported.size == 1
      pend "More than one protocol version must be supported"
    end

    # Server sets min_version (earliest is disabled)
    sver = supported[1]
    sctx = make_server_context
    sctx.security_level = 0
    sctx.min_version = sver

    start_server(sctx, ignore_listener_error: true) { |port|
      supported.each do |cver|
        # Client sets min_version
        ctx1 = OpenSSL::SSL::SSLContext.new
        ctx1.security_level = 0
        ctx1.min_version = cver
        ctx1.max_version = 0
        server_connect(port, ctx1) { |ssl|
          assert_equal vmap[supported.last][:name], ssl.ssl_version
          ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        }

        # Client sets max_version
        ctx2 = OpenSSL::SSL::SSLContext.new
        ctx2.security_level = 0
        ctx2.min_version = 0
        ctx2.max_version = cver
        if cver >= sver
          server_connect(port, ctx2) { |ssl|
            assert_equal vmap[cver][:name], ssl.ssl_version
            ssl.puts "abc"; assert_equal "abc\n", ssl.gets
          }
        else
          assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx2) }
        end
      end
    }

    # Server sets max_version (latest is disabled)
    sver = supported[-2]
    sctx = make_server_context
    sctx.security_level = 0
    sctx.min_version = 0
    sctx.max_version = sver

    start_server(sctx, ignore_listener_error: true) { |port|
      supported.each do |cver|
        # Client sets min_version
        ctx1 = OpenSSL::SSL::SSLContext.new
        ctx1.min_version = cver
        if cver <= sver
          server_connect(port, ctx1) { |ssl|
            assert_equal vmap[sver][:name], ssl.ssl_version
            ssl.puts "abc"; assert_equal "abc\n", ssl.gets
          }
        else
          assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx1) }
        end

        # Client sets max_version
        ctx2 = OpenSSL::SSL::SSLContext.new
        ctx2.security_level = 0
        ctx2.min_version = 0
        ctx2.max_version = cver
        server_connect(port, ctx2) { |ssl|
          if cver >= sver
            assert_equal vmap[sver][:name], ssl.ssl_version
          else
            assert_equal vmap[cver][:name], ssl.ssl_version
          end
          ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        }
      end
    }
  end

  def test_minmax_version_system_default
    omit "LibreSSL and AWS-LC do not support OPENSSL_CONF" if libressl? || aws_lc?

    Tempfile.create("openssl.cnf") { |f|
      f.puts(<<~EOF)
        openssl_conf = default_conf
        [default_conf]
        ssl_conf = ssl_sect
        [ssl_sect]
        system_default = ssl_default_sect
        [ssl_default_sect]
        MaxProtocol = TLSv1.2
      EOF
      f.close

      start_server(ignore_listener_error: true) do |port|
        assert_separately([{ "OPENSSL_CONF" => f.path }, "-ropenssl", "-", port.to_s], <<~"end;")
          sock = TCPSocket.new("127.0.0.1", ARGV[0].to_i)
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.sync_close = true
          ssl.connect
          assert_equal("TLSv1.2", ssl.ssl_version)
          ssl.puts("abc"); assert_equal("abc\n", ssl.gets)
          ssl.close
        end;

        assert_separately([{ "OPENSSL_CONF" => f.path }, "-ropenssl", "-", port.to_s], <<~"end;")
          sock = TCPSocket.new("127.0.0.1", ARGV[0].to_i)
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
          ctx.max_version = nil
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.sync_close = true
          ssl.connect
          assert_equal("TLSv1.3", ssl.ssl_version)
          ssl.puts("abc"); assert_equal("abc\n", ssl.gets)
          ssl.close
        end;
      end
    }
  end

  def test_respect_system_default_min
    omit "LibreSSL and AWS-LC do not support OPENSSL_CONF" if libressl? || aws_lc?

    Tempfile.create("openssl.cnf") { |f|
      f.puts(<<~EOF)
        openssl_conf = default_conf
        [default_conf]
        ssl_conf = ssl_sect
        [ssl_sect]
        system_default = ssl_default_sect
        [ssl_default_sect]
        MinProtocol = TLSv1.3
      EOF
      f.close

      sctx = make_server_context
      sctx.min_version = sctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
      start_server(sctx, ignore_listener_error: true) do |port|
        assert_separately([{ "OPENSSL_CONF" => f.path }, "-ropenssl", "-", port.to_s], <<~"end;")
          sock = TCPSocket.new("127.0.0.1", ARGV[0].to_i)
          ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.sync_close = true
          assert_raise(OpenSSL::SSL::SSLError) do
            ssl.connect
          end
          ssl.close
        end;
      end

      sctx = make_server_context
      sctx.min_version = sctx.max_version = OpenSSL::SSL::TLS1_3_VERSION
      start_server(sctx, ignore_listener_error: true) do |port|
        assert_separately([{ "OPENSSL_CONF" => f.path }, "-ropenssl", "-", port.to_s], <<~"end;")
          sock = TCPSocket.new("127.0.0.1", ARGV[0].to_i)
          ctx = OpenSSL::SSL::SSLContext.new
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.sync_close = true
          ssl.connect
          assert_equal("TLSv1.3", ssl.ssl_version)
          ssl.puts("abc"); assert_equal("abc\n", ssl.gets)
          ssl.close
        end;
      end
    }
  end

  def test_options_disable_versions
    # It's recommended to use SSLContext#{min,max}_version= instead in real
    # applications. The purpose of this test case is to check that SSL options
    # are properly propagated to OpenSSL library.
    supported = check_supported_protocol_versions
    if !supported.include?(OpenSSL::SSL::TLS1_2_VERSION) ||
        !supported.include?(OpenSSL::SSL::TLS1_3_VERSION)
      pend "this test case requires both TLS 1.2 and TLS 1.3 to be supported " \
        "and enabled by default"
    end

    # Server disables TLS 1.2 and earlier
    sctx = make_server_context
    sctx.options |= OpenSSL::SSL::OP_NO_SSLv2 | OpenSSL::SSL::OP_NO_SSLv3 |
      OpenSSL::SSL::OP_NO_TLSv1 | OpenSSL::SSL::OP_NO_TLSv1_1 |
      OpenSSL::SSL::OP_NO_TLSv1_2
    start_server(sctx, ignore_listener_error: true) { |port|
      # Client only supports TLS 1.2
      ctx1 = OpenSSL::SSL::SSLContext.new
      ctx1.min_version = ctx1.max_version = OpenSSL::SSL::TLS1_2_VERSION
      assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx1) }

      # Client only supports TLS 1.3
      ctx2 = OpenSSL::SSL::SSLContext.new
      ctx2.min_version = ctx2.max_version = OpenSSL::SSL::TLS1_3_VERSION
      assert_nothing_raised { server_connect(port, ctx2) { } }
    }

    # Server only supports TLS 1.2
    sctx = make_server_context
    sctx.min_version = sctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
    start_server(sctx, ignore_listener_error: true) { |port|
      # Client doesn't support TLS 1.2
      ctx1 = OpenSSL::SSL::SSLContext.new
      ctx1.options |= OpenSSL::SSL::OP_NO_TLSv1_2
      assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx1) }

      # Client supports TLS 1.2 by default
      ctx2 = OpenSSL::SSL::SSLContext.new
      ctx2.options |= OpenSSL::SSL::OP_NO_TLSv1_3
      assert_nothing_raised { server_connect(port, ctx2) { } }
    }
  end

  def test_ssl_methods_constant
    EnvUtil.suppress_warning { # Deprecated in v2.1.0
      base = [:TLSv1_2, :TLSv1_1, :TLSv1, :SSLv3, :SSLv2, :SSLv23]
      base.each do |name|
        assert_include OpenSSL::SSL::SSLContext::METHODS, name
        assert_include OpenSSL::SSL::SSLContext::METHODS, :"#{name}_client"
        assert_include OpenSSL::SSL::SSLContext::METHODS, :"#{name}_server"
      end
    }
  end

  def test_renegotiation_cb
    num_handshakes = 0
    sctx = make_server_context
    sctx.renegotiation_cb = -> ssl {
      num_handshakes += 1
      assert_kind_of(OpenSSL::SSL::SSLSocket, ssl)
    }

    start_server(sctx) { |port|
      server_connect(port) { |ssl|
        assert_equal(1, num_handshakes)
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }
    }
  end

  def test_alpn_protocol_selection_ary
    advertised = ["http/1.1", "spdy/2"]
    sctx = make_server_context
    sctx.alpn_select_cb = -> protocols { protocols.first }

    start_server(sctx) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.alpn_protocols = advertised
      server_connect(port, ctx) { |ssl|
        assert_equal(advertised.first, ssl.alpn_protocol)
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }
    }
  end

  def test_alpn_protocol_selection_cancel
    server_proc = proc do |sock|
      sctx = make_server_context
      sctx.alpn_select_cb = -> (protocols) { nil }
      ssl = OpenSSL::SSL::SSLSocket.new(sock, sctx)
      assert_raise_with_message(TypeError, /nil/) { ssl.accept }
    end
    start_server_proc(server_proc) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.alpn_protocols = ["http/1.1"]
      # no_application_protocol alert
      assert_raise_with_message(OpenSSL::SSL::SSLError, /alert number 120/) {
        server_connect(port, ctx) { }
      }
    end
  end

  def test_npn_protocol_selection_ary
    return unless OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)

    advertised = ["http/1.1", "spdy/2"]
    sctx = make_server_context
    sctx.npn_protocols = advertised

    start_server(sctx) { |port|
      selector = lambda { |which|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.max_version = :TLS1_2
        ctx.npn_select_cb = -> (protocols) { protocols.send(which) }
        server_connect(port, ctx) { |ssl|
          assert_equal(advertised.send(which), ssl.npn_protocol)
        }
      }
      selector.call(:first)
      selector.call(:last)
    }
  end

  def test_npn_protocol_selection_enum
    return unless OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)

    advertised = Object.new
    def advertised.each
      yield "http/1.1"
      yield "spdy/2"
    end
    sctx = make_server_context
    sctx.npn_protocols = advertised

    start_server(sctx) { |port|
      selector = lambda { |selected, which|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.max_version = :TLS1_2
        ctx.npn_select_cb = -> (protocols) { protocols.to_a.send(which) }
        server_connect(port, ctx) { |ssl|
          assert_equal(selected, ssl.npn_protocol)
        }
      }
      selector.call("http/1.1", :first)
      selector.call("spdy/2", :last)
    }
  end

  def test_npn_protocol_selection_cancel
    return unless OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)

    sctx = make_server_context
    sctx.npn_protocols = ["http/1.1"]

    start_server(sctx, ignore_listener_error: true) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.max_version = :TLS1_2
      ctx.npn_select_cb = -> (protocols) { raise RuntimeError.new }
      assert_raise(RuntimeError) { server_connect(port, ctx) }
    }
  end

  def test_npn_advertised_protocol_too_long
    return unless OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)

    ctx = OpenSSL::SSL::SSLContext.new
    assert_raise(OpenSSL::SSL::SSLError) do
      ctx.npn_protocols = ["a" * 256]
      ctx.setup
    end
  end

  def test_npn_selected_protocol_too_long
    return unless OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)

    sctx = make_server_context
    sctx.npn_protocols = ["http/1.1"]

    start_server(sctx, ignore_listener_error: true) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.max_version = :TLS1_2
      ctx.npn_select_cb = -> (protocols) { "a" * 256 }
      assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx) }
    }
  end

  def test_close_after_socket_close
    # The client closes the TCP socket without SSLSocket#stop
    sctx = make_server_context
    if defined?(OpenSSL::SSL::OP_IGNORE_UNEXPECTED_EOF)
      sctx.options |= OpenSSL::SSL::OP_IGNORE_UNEXPECTED_EOF
    end

    start_server(sctx) { |port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.connect
      ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      sock.close
      assert_nothing_raised do
        ssl.close
      end
    }
  end

  def test_sync_close_without_connect
    Socket.open(:INET, :STREAM) {|s|
      ssl = OpenSSL::SSL::SSLSocket.new(s)
      ssl.sync_close = true
      ssl.close
      assert(s.closed?)
    }
  end

  def test_get_ephemeral_key
    # kRSA is not FIPS-approved.
    omit_on_fips

    # kRSA
    sctx = make_server_context
    sctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
    sctx.ciphers = "kRSA"
    start_server(sctx, ignore_listener_error: true) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
      ctx.ciphers = "kRSA"
      begin
        server_connect(port, ctx) { |ssl| assert_nil ssl.tmp_key }
      rescue OpenSSL::SSL::SSLError
        # kRSA seems disabled
        raise unless $!.message =~ /no cipher/
      end
    end

    # DHE
    # OpenSSL 3.0 added support for named FFDHE groups in TLS 1.3
    # LibreSSL does not support named FFDHE groups currently
    # AWS-LC does not support DHE ciphersuites
    if openssl?(3, 0, 0)
      start_server do |port|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.groups = "ffdhe3072"
        server_connect(port, ctx) { |ssl|
          assert_instance_of OpenSSL::PKey::DH, ssl.tmp_key
          assert_equal 3072, ssl.tmp_key.p.num_bits
          ssl.puts "abc"; assert_equal "abc\n", ssl.gets
        }
      end
    end

    # ECDHE
    sctx = make_server_context
    sctx.groups = "P-256"
    start_server(sctx) do |port|
      server_connect(port) { |ssl|
        assert_instance_of OpenSSL::PKey::EC, ssl.tmp_key
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }
    end
  end

  def test_fallback_scsv
    supported = check_supported_protocol_versions
    unless supported.include?(OpenSSL::SSL::TLS1_1_VERSION)
      omit "TLS 1.1 support is required to run this test case"
    end

    omit "Fallback SCSV is not supported" if libressl?

    start_server do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
      # Here is OK
      # TLS1.2 supported and this is what we ask the first time
      server_connect(port, ctx)
    end

    sctx = make_server_context
    sctx.security_level = 0
    sctx.min_version = 0
    sctx.max_version = OpenSSL::SSL::TLS1_1_VERSION
    start_server(sctx) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.enable_fallback_scsv
      ctx.security_level = 0
      ctx.min_version = 0
      ctx.max_version = OpenSSL::SSL::TLS1_1_VERSION
      # Here is OK too
      # TLS1.2 not supported, fallback to TLS1.1 and signaling the fallback
      # Server doesn't support better, so connection OK
      server_connect(port, ctx)
    end

    # Here is not OK
    # TLS1.2 is supported, fallback to TLS1.1 (downgrade attack) and signaling the fallback
    # Server support better, so refuse the connection
    server_proc = proc do |sock|
      # This test is for the downgrade protection mechanism of TLS1.2.
      # This is why ctx1 bounds max_version == TLS1.2.
      # Otherwise, this test fails when using openssl 1.1.1 (or later) that supports TLS1.3.
      # TODO: We may need another test for TLS1.3 because it seems to have a different mechanism.
      ctx1 = OpenSSL::SSL::SSLContext.new
      ctx1.security_level = 0
      ctx1.min_version = 0
      ctx1.max_version = OpenSSL::SSL::TLS1_2_VERSION
      s1 = OpenSSL::SSL::SSLSocket.new(sock, ctx1)
      # AWS-LC has slightly different error messages in all-caps.
      assert_raise_with_message(OpenSSL::SSL::SSLError, /inappropriate.fallback/i) {
        s1.accept
      }
    end
    start_server_proc(server_proc) do |port|
      ctx2 = OpenSSL::SSL::SSLContext.new
      ctx2.enable_fallback_scsv
      ctx2.security_level = 0
      ctx2.min_version = 0
      ctx2.max_version = OpenSSL::SSL::TLS1_1_VERSION
      assert_raise_with_message(OpenSSL::SSL::SSLError, /inappropriate.fallback/i) {
        server_connect(port, ctx2) { }
      }
    end
  end

  def test_tmp_dh_callback
    # DH missing the q value on unknown named parameters is not FIPS-approved.
    omit_on_fips
    omit "AWS-LC does not support DHE ciphersuites" if aws_lc?

    dh = Fixtures.pkey("dh-1")
    called = false

    sctx = make_server_context
    sctx.max_version = :TLS1_2
    sctx.ciphers = "DH:!NULL"
    sctx.tmp_dh_callback = ->(*args) {
      called = true
      dh
    }

    start_server(sctx) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.groups = "P-256" # Exclude RFC 7919 groups
      server_connect(port, ctx) { |ssl|
        assert called, "dh callback should be called"
        assert_equal dh.to_der, ssl.tmp_key.to_der
      }
    end
  end

  def test_ciphersuites_method_tls_connection
    csuite = ['TLS_AES_128_GCM_SHA256', 'TLSv1.3', 128, 128]
    inputs = [csuite[0], [csuite[0]], [csuite]]

    start_server do |port|
      inputs.each do |input|
        cli_ctx = OpenSSL::SSL::SSLContext.new
        cli_ctx.min_version = cli_ctx.max_version = OpenSSL::SSL::TLS1_3_VERSION
        cli_ctx.ciphersuites = input

        server_connect(port, cli_ctx) do |ssl|
          assert_equal('TLSv1.3', ssl.ssl_version)
          assert_equal(csuite[0], ssl.cipher[0])
          ssl.puts('abc'); assert_equal("abc\n", ssl.gets)
        end
      end
    end
  end

  def test_ciphersuites_method_nil_argument
    ssl_ctx = OpenSSL::SSL::SSLContext.new
    assert_nothing_raised { ssl_ctx.ciphersuites = nil }
  end

  def test_ciphersuites_method_frozen_object
    ssl_ctx = OpenSSL::SSL::SSLContext.new
    ssl_ctx.freeze
    assert_raise(FrozenError) { ssl_ctx.ciphersuites = 'TLS_AES_256_GCM_SHA384' }
  end

  def test_ciphersuites_method_bogus_csuite
    ssl_ctx = OpenSSL::SSL::SSLContext.new
    # AWS-LC has slightly different error messages in all-caps.
    assert_raise_with_message(
      OpenSSL::SSL::SSLError,
      /SSL_CTX_set_ciphersuites: (no cipher match|NO_CIPHER_MATCH)/i
    ) { ssl_ctx.ciphersuites = 'BOGUS' }
  end

  def test_ciphers_method_tls_connection
    csuite = ['ECDHE-RSA-AES256-GCM-SHA384', 'TLSv1.2', 256, 256]
    inputs = [csuite[0], [csuite[0]], [csuite]]

    start_server do |port|
      inputs.each do |input|
        cli_ctx = OpenSSL::SSL::SSLContext.new
        cli_ctx.min_version = cli_ctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
        cli_ctx.ciphers = input

        server_connect(port, cli_ctx) do |ssl|
          assert_equal('TLSv1.2', ssl.ssl_version)
          assert_equal(csuite[0], ssl.cipher[0])
          ssl.puts('abc'); assert_equal("abc\n", ssl.gets)
        end
      end
    end
  end

  def test_ciphers_method_nil_argument
    ssl_ctx = OpenSSL::SSL::SSLContext.new
    assert_nothing_raised { ssl_ctx.ciphers = nil }
  end

  def test_ciphers_method_frozen_object
    ssl_ctx = OpenSSL::SSL::SSLContext.new

    ssl_ctx.freeze
    assert_raise(FrozenError) { ssl_ctx.ciphers = 'ECDHE-RSA-AES128-SHA' }
  end

  def test_ciphers_method_bogus_csuite
    ssl_ctx = OpenSSL::SSL::SSLContext.new

    # AWS-LC has slightly different error messages in all-caps.
    assert_raise_with_message(
      OpenSSL::SSL::SSLError,
      /SSL_CTX_set_cipher_list: (no cipher match|NO_CIPHER_MATCH)/i
    ) { ssl_ctx.ciphers = 'BOGUS' }
  end

  def test_sigalgs
    omit "SSL_CTX_set1_sigalgs_list() not supported" if libressl?

    svr_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
      ["subjectAltName", "DNS:localhost", false],
    ]
    ecdsa_key = Fixtures.pkey("p256")
    ecdsa_cert = issue_cert(@svr, ecdsa_key, 10, svr_exts, @ca_cert, @ca_key)

    sctx = OpenSSL::SSL::SSLContext.new
    sctx.add_certificate(@svr_cert, @svr_key, [@ca_cert]) # RSA
    sctx.add_certificate(ecdsa_cert, ecdsa_key, [@ca_cert]) # ECDSA

    start_server(sctx) do |port|
      ctx1 = OpenSSL::SSL::SSLContext.new
      ctx1.sigalgs = "rsa_pss_rsae_sha256"
      server_connect(port, ctx1) { |ssl|
        assert_kind_of(OpenSSL::PKey::RSA, ssl.peer_cert.public_key)
        ssl.puts("abc"); ssl.gets
      }

      ctx2 = OpenSSL::SSL::SSLContext.new
      ctx2.sigalgs = "ed25519:ecdsa_secp256r1_sha256"
      server_connect(port, ctx2) { |ssl|
        assert_kind_of(OpenSSL::PKey::EC, ssl.peer_cert.public_key)
        ssl.puts("abc"); ssl.gets
      }
    end

    # Frozen
    ssl_ctx = OpenSSL::SSL::SSLContext.new
    ssl_ctx.freeze
    assert_raise(FrozenError) { ssl_ctx.sigalgs = "ECDSA+SHA256:RSA+SHA256" }

    # Bogus
    ssl_ctx = OpenSSL::SSL::SSLContext.new
    assert_raise(TypeError) { ssl_ctx.sigalgs = nil }
    assert_raise(OpenSSL::SSL::SSLError) { ssl_ctx.sigalgs = "BOGUS" }
  end

  def test_client_sigalgs
    omit "SSL_CTX_set1_client_sigalgs_list() not supported" if libressl? || aws_lc?

    cli_exts = [
      ["keyUsage", "keyEncipherment,digitalSignature", true],
      ["subjectAltName", "DNS:localhost", false],
    ]
    ecdsa_key = Fixtures.pkey("p256")
    ecdsa_cert = issue_cert(@cli, ecdsa_key, 10, cli_exts, @ca_cert, @ca_key)

    store = OpenSSL::X509::Store.new
    store.add_cert(@ca_cert)
    store.purpose = OpenSSL::X509::PURPOSE_SSL_CLIENT
    sctx = make_server_context
    sctx.cert_store = store
    sctx.verify_mode =
      OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    sctx.client_sigalgs = "ECDSA+SHA256"

    start_server(sctx, ignore_listener_error: true) do |port|
      ctx1 = OpenSSL::SSL::SSLContext.new
      ctx1.add_certificate(@cli_cert, @cli_key) # RSA
      assert_raise(OpenSSL::SSL::SSLError) {
        server_connect(port, ctx1) { |ssl|
          ssl.puts("abc"); ssl.gets
        }
      }

      ctx2 = OpenSSL::SSL::SSLContext.new
      ctx2.add_certificate(ecdsa_cert, ecdsa_key) # ECDSA
      server_connect(port, ctx2) { |ssl|
        ssl.puts("abc"); ssl.gets
      }
    end
  end

  def test_get_sigalg
    # SSL_get0_signature_name() not supported
    # SSL_get0_peer_signature_name() not supported
    return unless openssl?(3, 5, 0)

    server_proc = proc do |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, make_server_context).accept
      assert_equal('rsa_pss_rsae_sha256', ssl.sigalg)
      assert_nil(ssl.peer_sigalg)

      readwrite_loop(ssl)
    end
    start_server_proc(server_proc) do |port|
      cli_ctx = OpenSSL::SSL::SSLContext.new
      server_connect(port, cli_ctx) do |ssl|
        assert_nil(ssl.sigalg)
        assert_equal('rsa_pss_rsae_sha256', ssl.peer_sigalg)
        ssl.puts "abc"; ssl.gets
      end
    end
  end

  def test_pqc_sigalg
    # PQC algorithm ML-DSA (FIPS 204) is supported on OpenSSL 3.5 or later.
    return unless openssl?(3, 5, 0)

    mldsa = Fixtures.pkey("mldsa65-1")
    mldsa_ca_key  = Fixtures.pkey("mldsa65-2")
    mldsa_ca_cert = issue_cert(@ca, mldsa_ca_key, 1, @ca_exts, nil, nil,
                               digest: nil)
    mldsa_cert = issue_cert(@svr, mldsa, 60, [], mldsa_ca_cert, mldsa_ca_key,
                            digest: nil)
    rsa = Fixtures.pkey("rsa-1")
    rsa_cert = issue_cert(@svr, rsa, 61, [], @ca_cert, @ca_key)

    sctx = OpenSSL::SSL::SSLContext.new
    sctx.sigalgs = "rsa_pss_rsae_sha256:mldsa65"
    sctx.add_certificate(mldsa_cert, mldsa)
    sctx.add_certificate(rsa_cert, rsa)

    server_proc = proc do |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, sctx).accept
      assert_equal('mldsa65', ssl.sigalg)
      readwrite_loop(ssl)
    end
    start_server_proc(server_proc) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      # Set signature algorithm because while OpenSSL may use ML-DSA by
      # default, the system OpenSSL configuration affects the used signature
      # algorithm.
      ctx.sigalgs = 'mldsa65'
      server_connect(port, ctx) { |ssl|
        assert_equal('mldsa65', ssl.peer_sigalg)
        ssl.puts "abc"; ssl.gets
      }
    end

    server_proc = proc do |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, sctx).accept
      assert_equal('rsa_pss_rsae_sha256', ssl.sigalg)
      readwrite_loop(ssl)
    end
    start_server_proc(server_proc) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.sigalgs = 'rsa_pss_rsae_sha256'
      server_connect(port, ctx) { |ssl|
        assert_equal('rsa_pss_rsae_sha256', ssl.peer_sigalg)
        ssl.puts "abc"; ssl.gets
      }
    end
  end

  def test_connect_works_when_setting_dh_callback_to_nil
    omit "AWS-LC does not support DHE ciphersuites" if aws_lc?

    sctx = make_server_context
    sctx.max_version = :TLS1_2
    sctx.ciphers = "DH:!NULL" # use DH
    sctx.tmp_dh_callback = nil

    start_server(sctx) do |port|
      assert_nothing_raised { server_connect(port) { } }
    end
  end

  def test_tmp_dh
    # DH missing the q value on unknown named parameters is not FIPS-approved.
    omit_on_fips
    omit "AWS-LC does not support DHE ciphersuites" if aws_lc?

    dh = Fixtures.pkey("dh-1")
    sctx = make_server_context
    sctx.max_version = :TLS1_2
    sctx.ciphers = "DH:!NULL" # use DH
    sctx.tmp_dh = dh

    start_server(sctx) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.groups = "P-256" # Exclude RFC 7919 groups
      server_connect(port, ctx) { |ssl|
        assert_equal dh.to_der, ssl.tmp_key.to_der
      }
    end
  end

  def test_set_groups_tls12
    # Enable both ECDHE (~ TLS 1.2) cipher suites and TLS 1.3
    sctx = make_server_context
    sctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
    sctx.ciphers = "kEECDH"
    sctx.groups = "P-384:P-521"

    start_server(sctx, ignore_listener_error: true) do |port|
      # Test 1: Client=P-256:P-384, Server=P-384:P-521 --> P-384
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.groups = "P-256:P-384"
      server_connect(port, ctx) { |ssl|
        cs = ssl.cipher[0]
        assert_match (/\AECDH/), cs
        # SSL_get0_group_name() is supported on OpenSSL 3.2 or later.
        assert_equal "secp384r1", ssl.group if openssl?(3, 2, 0)
        assert_equal "secp384r1", ssl.tmp_key.group.curve_name
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }

      # Test 2: Client=P-256, Server=P-521:P-384 --> Fail
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.groups = "P-256"
      assert_raise(OpenSSL::SSL::SSLError) {
        server_connect(port, ctx) { }
      }

      # Test 3: Client=P-521:P-384, Server=P-521:P-384 --> P-521
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.groups = "P-521:P-384"
      server_connect(port, ctx) { |ssl|
        assert_equal "secp521r1", ssl.tmp_key.group.curve_name
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }

      # Test 4: #ecdh_curves= alias
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ecdh_curves = "P-256:P-384"
      server_connect(port, ctx) { |ssl|
        assert_equal "secp384r1", ssl.tmp_key.group.curve_name
      }
    end
  end

  def test_set_groups_tls13
    # Assume TLS 1.3 is enabled and chosen by default
    sctx = make_server_context
    sctx.groups = "P-384:P-521"

    start_server(sctx) do |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.groups = "P-256:P-384" # disable P-521

      server_connect(port, ctx) { |ssl|
        assert_equal "TLSv1.3", ssl.ssl_version
        # SSL_get0_group_name() is supported on OpenSSL 3.2 or later.
        assert_equal "secp384r1", ssl.group if openssl?(3, 2, 0)
        assert_equal "secp384r1", ssl.tmp_key.group.curve_name
        ssl.puts "abc"; assert_equal "abc\n", ssl.gets
      }
    end
  end

  def test_pqc_group
    # PQC algorithm ML-KEM (FIPS 203) is supported on OpenSSL 3.5 or later.
    return unless openssl?(3, 5, 0)

    [
      'X25519MLKEM768',
      'SecP256r1MLKEM768',
      'SecP384r1MLKEM1024'
    ].each do |group|
      sctx = make_server_context
      sctx.groups = group

      start_server(sctx) do |port|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.groups = group
        server_connect(port, ctx) { |ssl|
          assert_equal(group, ssl.group)
          ssl.puts "abc"; ssl.gets
        }
      end
    end
  end

  def test_security_level
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.security_level = 1
    if aws_lc? # AWS-LC does not support security levels.
      assert_equal(0, ctx.security_level)
      return
    end
    assert_equal(1, ctx.security_level)

    # See SSL_CTX_set_security_level(3). Definitions of security levels may
    # change in future OpenSSL versions. As of OpenSSL 1.1.0:
    #  - Level 1 requires 160-bit ECC keys or 1024-bit RSA keys.
    #  - Level 2 requires 224-bit ECC keys or 2048-bit RSA keys.
    begin
      ec112 = OpenSSL::PKey::EC.generate("secp112r1")
      ec112_cert = issue_cert(@svr, ec112, 50, [], @ca_cert, @ca_key)
      ec192 = OpenSSL::PKey::EC.generate("prime192v1")
      ec192_cert = issue_cert(@svr, ec192, 51, [], @ca_cert, @ca_key)
    rescue OpenSSL::PKey::PKeyError
      # Distro-provided OpenSSL may refuse to generate small keys
      return
    end

    assert_raise(OpenSSL::SSL::SSLError) {
      ctx.add_certificate(ec112_cert, ec112)
    }
    assert_nothing_raised {
      ctx.add_certificate(ec192_cert, ec192)
    }
    ctx.security_level = 2
    assert_raise(OpenSSL::SSL::SSLError) {
      # < 112 bits of security
      ctx.add_certificate(ec192_cert, ec192)
    }
  end

  def test_dup
    ctx = OpenSSL::SSL::SSLContext.new
    Socket.open(:INET, :STREAM) { |sock|
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)

      assert_raise(NoMethodError) { ctx.dup }
      assert_raise(NoMethodError) { ssl.dup }
    }
  end

  def test_freeze_calls_setup
    bug = "[ruby/openssl#85]"
    start_server(ignore_listener_error: true) { |port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ctx.freeze
      assert_raise(OpenSSL::SSL::SSLError, bug) {
        server_connect(port, ctx)
      }
    }
  end

  def test_fileno
    Socket.open(:INET, :STREAM) { |sock|
      ctx = OpenSSL::SSL::SSLContext.new
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      server = OpenSSL::SSL::SSLServer.new(sock, ctx)

      assert_equal(sock.fileno, ssl.fileno)
      assert_equal(sock.fileno, server.fileno)
    }
  end

  def test_export_keying_material
    start_server do |port|
      cli_ctx = OpenSSL::SSL::SSLContext.new
      server_connect(port, cli_ctx) do |ssl|
        assert_instance_of(String, ssl.export_keying_material('ttls keying material', 64))
        assert_operator(64, :==, ssl.export_keying_material('ttls keying material', 64).b.length)
        assert_operator(8, :==, ssl.export_keying_material('ttls keying material', 8).b.length)
        assert_operator(5, :==, ssl.export_keying_material('test', 5, 'context').b.length)
        ssl.puts "abc"; ssl.gets # workaround to make tests work on windows
      end
    end
  end

  # OpenSSL::Buffering requires $/ accessible from non-main Ractors (Ruby 4.0)
  # https://bugs.ruby-lang.org/issues/21109
  #
  # Hangs on Windows
  # https://bugs.ruby-lang.org/issues/21537
  if respond_to?(:ractor) && RUBY_VERSION >= "4.0" && RUBY_PLATFORM !~ /mswin|mingw/
    ractor
    def test_ractor_client
      start_server { |port|
        s = Ractor.new(port, @ca_cert) { |port, ca_cert|
          sock = TCPSocket.new("127.0.0.1", port)
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
          ctx.cert_store = OpenSSL::X509::Store.new.tap { |store|
            store.add_cert(ca_cert)
          }
          begin
            ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
            ssl.connect
            ssl.puts("abc")
            ssl.gets
          ensure
            ssl.close
            sock.close
          end
        }.value
        assert_equal("abc\n", s)
      }
    end

    ractor
    def test_ractor_set_params
      # We cannot actually test default stores in the test suite as it depends
      # on the environment, but at least check that it does not raise an
      # exception
      ok = Ractor.new {
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.set_params
        ctx.cert_store.kind_of?(OpenSSL::X509::Store)
      }.value
      assert(ok, "ctx.cert_store is an instance of OpenSSL::X509::Store")
    end
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

end
