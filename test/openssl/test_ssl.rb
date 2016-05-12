# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestSSL < OpenSSL::SSLTestCase

  def test_ctx_setup
    ctx = OpenSSL::SSL::SSLContext.new
    assert_equal(ctx.setup, true)
    assert_equal(ctx.setup, nil)
  end

  def test_ctx_setup_invalid
    m = OpenSSL::SSL::SSLContext::METHODS.first
    assert_raise_with_message(ArgumentError, /null/) {
      OpenSSL::SSL::SSLContext.new("#{m}\0")
    }
    assert_raise_with_message(ArgumentError, /\u{ff33 ff33 ff2c}/) {
      OpenSSL::SSL::SSLContext.new("\u{ff33 ff33 ff2c}")
    }
  end

  def test_options_defaults_to_OP_ALL_on
    ctx = OpenSSL::SSL::SSLContext.new
    assert_equal(OpenSSL::SSL::OP_ALL, (OpenSSL::SSL::OP_ALL & ctx.options))
  end

  def test_setting_twice
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.options = 4
    assert_equal 4, (ctx.options & OpenSSL::SSL::OP_ALL)
    ctx.options = OpenSSL::SSL::OP_ALL
    assert_equal OpenSSL::SSL::OP_ALL, (ctx.options & OpenSSL::SSL::OP_ALL)
  end

  def test_options_setting_nil_means_all
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.options = nil
    assert_equal(OpenSSL::SSL::OP_ALL, (OpenSSL::SSL::OP_ALL & ctx.options))
  end

  def test_setting_options_raises_after_setup
    ctx = OpenSSL::SSL::SSLContext.new
    options = ctx.options
    ctx.setup
    assert_raise(RuntimeError) do
      ctx.options = options
    end
  end

  def test_ctx_setup_no_compression
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_COMPRESSION
    assert_equal(ctx.setup, true)
    assert_equal(ctx.setup, nil)
    assert_equal(OpenSSL::SSL::OP_NO_COMPRESSION,
                 ctx.options & OpenSSL::SSL::OP_NO_COMPRESSION)
  end if defined?(OpenSSL::SSL::OP_NO_COMPRESSION)

  def test_ctx_setup_with_extra_chain_cert
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.extra_chain_cert = [@ca_cert, @cli_cert]
    assert_equal(ctx.setup, true)
    assert_equal(ctx.setup, nil)
  end

  def test_not_started_session
    skip "non socket argument of SSLSocket.new is not supported on this platform" if /mswin|mingw/ =~ RUBY_PLATFORM
    open(__FILE__) do |f|
      assert_nil OpenSSL::SSL::SSLSocket.new(f).cert
    end
  end

  def test_ssl_gets
    start_server(OpenSSL::SSL::VERIFY_NONE, true) { |server, port|
      server_connect(port) { |ssl|
        ssl.write "abc\n"
        IO.select [ssl]

        line = ssl.gets

        assert_equal "abc\n", line
        assert_equal Encoding::BINARY, line.encoding
      }
    }
  end

  def test_ssl_read_nonblock
    start_server(OpenSSL::SSL::VERIFY_NONE, true) { |server, port|
      server_connect(port) { |ssl|
        assert_raise(IO::WaitReadable) { ssl.read_nonblock(100) }
        ssl.write("abc\n")
        IO.select [ssl]
        assert_equal('a', ssl.read_nonblock(1))
        assert_equal("bc\n", ssl.read_nonblock(100))
        assert_raise(IO::WaitReadable) { ssl.read_nonblock(100) }
      }
    }
  end

  def test_ssl_sysread_blocking_error
    start_server(OpenSSL::SSL::VERIFY_NONE, true) { |server, port|
      server_connect(port) { |ssl|
        ssl.write("abc\n")
        assert_raise(TypeError) { ssl.sysread(4, exception: false) }
        buf = ''
        assert_raise(ArgumentError) { ssl.sysread(4, buf, exception: false) }
        assert_equal '', buf
        assert_equal buf.object_id, ssl.sysread(4, buf).object_id
        assert_equal "abc\n", buf
      }
    }
  end

  def test_connect_and_close
    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
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
    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      server_connect(port) { |ssl|
        # syswrite and sysread
        ITERATIONS.times{|i|
          str = "x" * 100 + "\n"
          ssl.syswrite(str)
          newstr = ''
          newstr << ssl.sysread(str.size - newstr.size) until newstr.size == str.size
          assert_equal(str, newstr)

          str = "x" * i * 100 + "\n"
          buf = ""
          ssl.syswrite(str)
          assert_equal(buf.object_id, ssl.sysread(str.size, buf).object_id)
          newstr = buf
          newstr << ssl.sysread(str.size - newstr.size) until newstr.size == str.size
          assert_equal(str, newstr)
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
      }
    }
  end

  def test_copy_stream
    start_server(OpenSSL::SSL::VERIFY_NONE, true) do |server, port|
      server_connect(port) do |ssl|
        IO.pipe do |r, w|
          str = "hello world\n"
          w.write(str)
          IO.copy_stream(r, ssl, str.bytesize)
          IO.copy_stream(ssl, w, str.bytesize)
          assert_equal str, r.read(str.bytesize)
        end
      end
    end
  end

  def test_client_auth_failure
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(vflag, true, :ignore_listener_error => true){|server, port|
      assert_raise(OpenSSL::SSL::SSLError, Errno::ECONNRESET){
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.sync_close = true
        begin
          ssl.connect
        ensure
          ssl.close
        end
      }
    }
  end

  def test_client_auth_success
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(vflag, true){|server, port|
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

  def test_client_ca
    ctx_proc = Proc.new do |ctx|
      ctx.client_ca = [@ca_cert]
    end

    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(vflag, true, :ctx_proc => ctx_proc){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      client_ca_from_server = nil
      ctx.client_cert_cb = Proc.new do |sslconn|
        client_ca_from_server = sslconn.client_ca
        [@cli_cert, @cli_key]
      end
      server_connect(port, ctx) { |ssl| assert_equal([@ca], client_ca_from_server) }
    }
  end

  def test_read_nonblock_without_session
    OpenSSL::TestUtils.silent do
      start_server(OpenSSL::SSL::VERIFY_NONE, false){|server, port|
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.sync_close = true

        assert_equal :wait_readable, ssl.read_nonblock(100, exception: false)
        ssl.write("abc\n")
        IO.select [ssl]
        assert_equal('a', ssl.read_nonblock(1))
        assert_equal("bc\n", ssl.read_nonblock(100))
        assert_equal :wait_readable, ssl.read_nonblock(100, exception: false)
        ssl.close
      }
    end
  end

  def test_starttls
    OpenSSL::TestUtils.silent do
      start_server(OpenSSL::SSL::VERIFY_NONE, false){|server, port|
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
  end

  def test_parallel
    GC.start
    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
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
    start_server(OpenSSL::SSL::VERIFY_NONE, true, :ignore_listener_error => true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
        assert_equal(OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN, ssl.verify_result)
      ensure
        ssl.close
      end
    }

    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(
        :verify_callback => Proc.new do |preverify_ok, store_ctx|
          store_ctx.error = OpenSSL::X509::V_OK
          true
        end
      )
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        ssl.connect
        assert_equal(OpenSSL::X509::V_OK, ssl.verify_result)
      ensure
        ssl.close
      end
    }

    start_server(OpenSSL::SSL::VERIFY_NONE, true, :ignore_listener_error => true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(
        :verify_callback => Proc.new do |preverify_ok, store_ctx|
          store_ctx.error = OpenSSL::X509::V_ERR_APPLICATION_VERIFICATION
          false
        end
      )
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
    start_server(OpenSSL::SSL::VERIFY_NONE, true, :ignore_listener_error => true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(
        :verify_callback => Proc.new do |preverify_ok, store_ctx|
          store_ctx.error = OpenSSL::X509::V_OK
          raise RuntimeError
        end
      )
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        OpenSSL::TestUtils.silent do
          # SSLError, not RuntimeError
          assert_raise(OpenSSL::SSL::SSLError) { ssl.connect }
        end
        assert_equal(OpenSSL::X509::V_ERR_CERT_REJECTED, ssl.verify_result)
      ensure
        ssl.close
      end
    }
  end

  def test_sslctx_set_params
    start_server(OpenSSL::SSL::VERIFY_NONE, true, :ignore_listener_error => true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      assert_equal(OpenSSL::SSL::VERIFY_PEER, ctx.verify_mode)
      assert_equal(OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options], ctx.options)
      ciphers = ctx.ciphers
      ciphers_versions = ciphers.collect{|_, v, _, _| v }
      ciphers_names = ciphers.collect{|v, _, _, _| v }
      assert(ciphers_names.all?{|v| /ADH/ !~ v })
      assert(ciphers_versions.all?{|v| /SSLv2/ !~ v })
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      begin
        assert_raise(OpenSSL::SSL::SSLError){ ssl.connect }
        assert_equal(OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN, ssl.verify_result)
      ensure
        ssl.close
      end
    }
  end

  def test_post_connect_check_with_anon_ciphers
    sslerr = OpenSSL::SSL::SSLError

    start_server(OpenSSL::SSL::VERIFY_NONE, true, {use_anon_cipher: true}){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ciphers = "aNULL"
      server_connect(port, ctx) { |ssl|
        msg = "Peer verification enabled, but no certificate received. Anonymous cipher suite " \
          "ADH-AES256-GCM-SHA384 was negotiated. Anonymous suites must be disabled to use peer verification."
        assert_raise_with_message(sslerr,msg){ssl.post_connection_check("localhost.localdomain")}
      }
    }
  end if OpenSSL::ExtConfig::TLS_DH_anon_WITH_AES_256_GCM_SHA384

  def test_post_connection_check
    sslerr = OpenSSL::SSL::SSLError

    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      server_connect(port) { |ssl|
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

    now = Time.now
    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:localhost.localdomain",false],
      ["subjectAltName","IP:127.0.0.1",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 4, now, now+1800, exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      server_connect(port) { |ssl|
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

    now = Time.now
    exts = [
      ["keyUsage","keyEncipherment,digitalSignature",true],
      ["subjectAltName","DNS:*.localdomain",false],
    ]
    @svr_cert = issue_cert(@svr, @svr_key, 5, now, now+1800, exts,
                           @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      server_connect(port) { |ssl|
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
      assert_equal(false, OpenSSL::SSL.verify_certificate_identity(cert, '13::17'))
      assert_equal(true,  OpenSSL::SSL.verify_certificate_identity(cert, '13:0:0:0:0:0:0:17'))
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

  # Comments in this test is excerpted from http://tools.ietf.org/html/rfc6125#page-27
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
    ef = OpenSSL::X509::ExtensionFactory.new
    cert = OpenSSL::X509::Certificate.new
    cert.subject = OpenSSL::X509::Name.parse("/DC=some/DC=site/CN=Some Site")
    ext = ef.create_ext('subjectAltName', san)
    cert.add_extension(ext)
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

  def socketpair
    if defined? UNIXSocket
      UNIXSocket.pair
    else
      Socket.pair(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    end
  end

  def test_servername_cb_sets_context_on_the_socket
    hostname = 'example.org'

    ctx3 = OpenSSL::SSL::SSLContext.new
    ctx3.ciphers = "DH"

    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.ciphers = "DH"
    ctx2.servername_cb = lambda { |args| ctx3 }

    sock1, sock2 = socketpair

    s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)

    ctx1 = OpenSSL::SSL::SSLContext.new
    ctx1.ciphers = "DH"

    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)
    s1.hostname = hostname
    t = Thread.new { s1.connect }

    assert_equal ctx2, s2.context
    accepted = s2.accept
    assert_equal ctx3, s2.context
    assert t.value
  ensure
    s1.close if s1
    s2.close if s2
    sock1.close if sock1
    sock2.close if sock2
    accepted.close if accepted.respond_to?(:close)
  end

  def test_servername_cb_raises_an_exception_on_unknown_objects
    hostname = 'example.org'

    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.ciphers = "DH"
    ctx2.servername_cb = lambda { |args| Object.new }

    sock1, sock2 = socketpair

    s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)

    ctx1 = OpenSSL::SSL::SSLContext.new
    ctx1.ciphers = "DH"

    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)
    s1.hostname = hostname
    t = Thread.new {
      assert_raise(OpenSSL::SSL::SSLError) do
        s1.connect
      end
    }

    assert_raise(ArgumentError) do
      s2.accept
    end

    assert t.join
  ensure
    sock1.close if sock1
    sock2.close if sock2
  end

  def test_servername_cb_calls_setup_on_returned_ctx
    hostname = 'example.org'

    ctx3 = OpenSSL::SSL::SSLContext.new
    ctx3.ciphers = "DH"
    assert_not_predicate ctx3, :frozen?

    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.ciphers = "DH"
    ctx2.servername_cb = lambda { |args| ctx3 }

    sock1, sock2 = socketpair

    s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)

    ctx1 = OpenSSL::SSL::SSLContext.new
    ctx1.ciphers = "DH"

    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)
    s1.hostname = hostname
    t = Thread.new { s1.connect }

    accepted = s2.accept
    assert t.value
    assert_predicate ctx3, :frozen?
  ensure
    s1.close if s1
    s2.close if s2
    sock1.close if sock1
    sock2.close if sock2
    accepted.close if accepted.respond_to?(:close)
  end

  def test_servername_cb_can_return_nil
    hostname = 'example.org'

    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.ciphers = "DH"
    ctx2.servername_cb = lambda { |args| nil }

    sock1, sock2 = socketpair

    s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)

    ctx1 = OpenSSL::SSL::SSLContext.new
    ctx1.ciphers = "DH"

    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)
    s1.hostname = hostname
    t = Thread.new { s1.connect }

    accepted = s2.accept
    assert t.value
  ensure
    s1.close if s1
    s2.close if s2
    sock1.close if sock1
    sock2.close if sock2
    accepted.close if accepted.respond_to?(:close)
  end

  def test_servername_cb
    lambda_called = nil
    cb_socket = nil
    hostname = 'example.org'

    ctx2 = OpenSSL::SSL::SSLContext.new
    ctx2.ciphers = "DH"
    ctx2.servername_cb = lambda do |args|
      cb_socket     = args[0]
      lambda_called = args[1]
      ctx2
    end

    sock1, sock2 = socketpair

    s2 = OpenSSL::SSL::SSLSocket.new(sock2, ctx2)

    ctx1 = OpenSSL::SSL::SSLContext.new
    ctx1.ciphers = "DH"

    s1 = OpenSSL::SSL::SSLSocket.new(sock1, ctx1)
    s1.hostname = hostname
    t = Thread.new { s1.connect }

    accepted = s2.accept
    assert t.value
    assert_equal hostname, lambda_called
    assert_equal s2, cb_socket
  ensure
    s1.close if s1
    s2.close if s2
    sock1.close if sock1
    sock2.close if sock2
    accepted.close if accepted.respond_to?(:close)
  end

  def test_tlsext_hostname
    return unless OpenSSL::SSL::SSLSocket.instance_methods.include?(:hostname)

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

    start_server(OpenSSL::SSL::VERIFY_NONE, true, :ctx_proc => ctx_proc, :server_proc => server_proc) do |server, port|
      2.times do |i|
        ctx = OpenSSL::SSL::SSLContext.new
        if defined?(OpenSSL::SSL::OP_NO_TICKET)
          # disable RFC4507 support
          ctx.options = OpenSSL::SSL::OP_NO_TICKET
        end
        server_connect(port, ctx) { |ssl|
          ssl.hostname = (i & 1 == 0) ? 'foo.example.com' : 'bar.example.com'
          str = "x" * 100 + "\n"
          ssl.puts(str)
          assert_equal(str, ssl.gets)
        }
      end
    end
  end

  def test_multibyte_read_write
    #German a umlaut
    auml = [%w{ C3 A4 }.join('')].pack('H*')
    auml.force_encoding(Encoding::UTF_8)

    [10, 1000, 100000].each {|i|
      str = nil
      num_written = nil
      server_proc = Proc.new {|ctx, ssl|
        cmp = ssl.read
        raw_size = cmp.size
        cmp.force_encoding(Encoding::UTF_8)
        assert_equal(str, cmp)
        assert_equal(num_written, raw_size)
        ssl.close
      }
      start_server(OpenSSL::SSL::VERIFY_NONE, true, :server_proc => server_proc){|server, port|
        server_connect(port) { |ssl|
          str = auml * i
          num_written = ssl.write(str)
        }
      }
    }
  end

  def test_unset_OP_ALL
    ctx_proc = Proc.new { |ctx|
      # If OP_DONT_INSERT_EMPTY_FRAGMENTS is not defined, this test is
      # redundant because the default options already are equal to OP_ALL.
      # But it also degrades gracefully, so keep it
      ctx.options = OpenSSL::SSL::OP_ALL
    }
    start_server(OpenSSL::SSL::VERIFY_NONE, true, :ctx_proc => ctx_proc){|server, port|
      server_connect(port) { |ssl|
        ssl.puts('hello')
        assert_equal("hello\n", ssl.gets)
      }
    }
  end

  # different OpenSSL versions react differently when facing a SSL/TLS version
  # that has been marked as forbidden, therefore either of these may be raised
  HANDSHAKE_ERRORS = [OpenSSL::SSL::SSLError, Errno::ECONNRESET]

if OpenSSL::SSL::SSLContext::METHODS.include?(:TLSv1) && OpenSSL::SSL::SSLContext::METHODS.include?(:SSLv3)

  def test_forbid_ssl_v3_for_client
    ctx_proc = Proc.new { |ctx| ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_SSLv3 }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :SSLv3
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end

  def test_forbid_ssl_v3_from_server
    start_server_version(:SSLv3) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_SSLv3
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end

end

if OpenSSL::SSL::SSLContext::METHODS.include? :TLSv1_1

  def test_tls_v1_1
    start_server_version(:TLSv1_1) { |server, port|
      server_connect(port) { |ssl| assert_equal("TLSv1.1", ssl.ssl_version) }
    }
  end

  def test_forbid_tls_v1_for_client
    ctx_proc = Proc.new { |ctx| ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_TLSv1 }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end

  def test_forbid_tls_v1_from_server
    start_server_version(:TLSv1) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_TLSv1
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end

end

if OpenSSL::SSL::SSLContext::METHODS.include? :TLSv1_2

  def test_tls_v1_2
    start_server_version(:TLSv1_2) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1_2_client
      server_connect(port, ctx) { |ssl| assert_equal("TLSv1.2", ssl.ssl_version) }
    }
  end if OpenSSL::OPENSSL_VERSION_NUMBER > 0x10001000

  def test_forbid_tls_v1_1_for_client
    ctx_proc = Proc.new { |ctx| ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_TLSv1_1 }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1_1
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end if defined?(OpenSSL::SSL::OP_NO_TLSv1_1)

  def test_forbid_tls_v1_1_from_server
    start_server_version(:TLSv1_1) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_TLSv1_1
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end if defined?(OpenSSL::SSL::OP_NO_TLSv1_1)

  def test_forbid_tls_v1_2_for_client
    ctx_proc = Proc.new { |ctx| ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_TLSv1_2 }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1_2
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end if defined?(OpenSSL::SSL::OP_NO_TLSv1_2)

  def test_forbid_tls_v1_2_from_server
    start_server_version(:TLSv1_2) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_TLSv1_2
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end if defined?(OpenSSL::SSL::OP_NO_TLSv1_2)

end

  def test_renegotiation_cb
    num_handshakes = 0
    renegotiation_cb = Proc.new { |ssl| num_handshakes += 1 }
    ctx_proc = Proc.new { |ctx| ctx.renegotiation_cb = renegotiation_cb }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      server_connect(port) { |ssl|
        assert_equal(1, num_handshakes)
      }
    }
  end

if OpenSSL::OPENSSL_VERSION_NUMBER >= 0x10002000
  def test_alpn_protocol_selection_ary
    advertised = ["http/1.1", "spdy/2"]
    ctx_proc = Proc.new { |ctx|
      ctx.alpn_select_cb = -> (protocols) {
        protocols.first
      }
      ctx.alpn_protocols = advertised
    }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.alpn_protocols = advertised
      server_connect(port, ctx) { |ssl|
        assert_equal(advertised.first, ssl.alpn_protocol)
      }
    }
  end

  def test_alpn_protocol_selection_cancel
    ctx_proc = Proc.new { |ctx|
      ctx.alpn_select_cb = -> (protocols) { nil }
    }
    assert_raise(MiniTest::Assertion) do # minitest/assertion comes from `assert_join_threads`
      start_server_version(:SSLv23, ctx_proc) { |server, port|
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.alpn_protocols = ["http/1.1"]
        assert_raise(OpenSSL::SSL::SSLError) { server_connect(port, ctx) }
      }
    end
  end
end

if OpenSSL::OPENSSL_VERSION_NUMBER > 0x10001000 &&
	OpenSSL::SSL::SSLContext.method_defined?(:npn_select_cb)
  # NPN may be disabled by OpenSSL configure option

  def test_npn_protocol_selection_ary
    advertised = ["http/1.1", "spdy/2"]
    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = advertised }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      selector = lambda { |which|
        ctx = OpenSSL::SSL::SSLContext.new
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
    advertised = Object.new
    def advertised.each
      yield "http/1.1"
      yield "spdy/2"
    end
    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = advertised }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      selector = lambda { |selected, which|
        ctx = OpenSSL::SSL::SSLContext.new
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
    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = ["http/1.1"] }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.npn_select_cb = -> (protocols) { raise RuntimeError.new }
      assert_raise(RuntimeError) { server_connect(port, ctx) }
    }
  end

  def test_npn_advertised_protocol_too_long
    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = ["a" * 256] }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.npn_select_cb = -> (protocols) { protocols.first }
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end

  def test_npn_selected_protocol_too_long
    ctx_proc = Proc.new { |ctx| ctx.npn_protocols = ["http/1.1"] }
    start_server_version(:SSLv23, ctx_proc) { |server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.npn_select_cb = -> (protocols) { "a" * 256 }
      assert_raise(*HANDSHAKE_ERRORS) { server_connect(port, ctx) }
    }
  end

end

  def test_invalid_shutdown_by_gc
    assert_nothing_raised {
      start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
        10.times {
          sock = TCPSocket.new("127.0.0.1", port)
          ssl = OpenSSL::SSL::SSLSocket.new(sock)
          GC.start
          ssl.connect
          sock.close
        }
      }
    }
  end

  def test_close_after_socket_close
    start_server(OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      ssl.connect
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
    return unless OpenSSL::SSL::SSLSocket.method_defined?(:tmp_key)
    pkey = OpenSSL::PKey
    ciphers = {
        'ECDHE-RSA-AES128-SHA' => (pkey::EC if defined?(pkey::EC)),
        'DHE-RSA-AES128-SHA' => (pkey::DH if defined?(pkey::DH)),
        'AES128-SHA' => nil
    }
    conf_proc = Proc.new { |ctx| ctx.ciphers = 'ALL' }
    start_server(OpenSSL::SSL::VERIFY_NONE, true, :ctx_proc => conf_proc) do |server, port|
      ciphers.each do |cipher, ephemeral|
        ctx = OpenSSL::SSL::SSLContext.new
        begin
          ctx.ciphers = cipher
        rescue OpenSSL::SSL::SSLError => e
          next if /no cipher match/ =~ e.message
          raise
        end
        server_connect(port, ctx) do |ssl|
          if ephemeral
            assert_instance_of(ephemeral, ssl.tmp_key)
          else
            assert_nil(ssl.tmp_key)
          end
        end
      end
    end
  end

  private

  def start_server_version(version, ctx_proc=nil, server_proc=nil, &blk)
    ctx_wrap = Proc.new { |ctx|
      ctx.ssl_version = version
      ctx_proc.call(ctx) if ctx_proc
    }
    start_server(
      OpenSSL::SSL::VERIFY_NONE,
      true,
      :ctx_proc => ctx_wrap,
      :server_proc => server_proc,
      :ignore_listener_error => true,
      &blk
    )
  end

  def server_connect(port, ctx=nil)
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
