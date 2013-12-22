require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestSSL < OpenSSL::SSLTestCase

  TLS_DEFAULT_OPS = defined?(OpenSSL::SSL::OP_DONT_INSERT_EMPTY_FRAGMENTS) ?
                    OpenSSL::SSL::OP_ALL & ~OpenSSL::SSL::OP_DONT_INSERT_EMPTY_FRAGMENTS :
                    OpenSSL::SSL::OP_ALL

  def test_ctx_setup
    ctx = OpenSSL::SSL::SSLContext.new
    assert_equal(ctx.setup, true)
    assert_equal(ctx.setup, nil)
  end

  def test_ctx_setup_no_compression
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.options = OpenSSL::SSL::OP_ALL | OpenSSL::SSL::OP_NO_COMPRESSION
    assert_equal(ctx.setup, true)
    assert_equal(ctx.setup, nil)
    assert_equal(OpenSSL::SSL::OP_NO_COMPRESSION,
                 ctx.options & OpenSSL::SSL::OP_NO_COMPRESSION)
  end if defined?(OpenSSL::SSL::OP_NO_COMPRESSION)

  def test_not_started_session
    skip "non socket argument of SSLSocket.new is not supported on this platform" if /mswin|mingw/ =~ RUBY_PLATFORM
    open(__FILE__) do |f|
      assert_nil OpenSSL::SSL::SSLSocket.new(f).cert
    end
  end

  def test_ssl_gets
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true) { |server, port|
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
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true) { |server, port|
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
      server_connect(port) { |ssl|
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
      }
    }
  end

  def test_client_auth
    vflag = OpenSSL::SSL::VERIFY_PEER|OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
    start_server(PORT, vflag, true){|server, port|
      assert_raise(OpenSSL::SSL::SSLError, Errno::ECONNRESET){
        sock = TCPSocket.new("127.0.0.1", port)
        ssl = OpenSSL::SSL::SSLSocket.new(sock)
        ssl.connect
      }

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
    start_server(PORT, vflag, true, :ctx_proc => ctx_proc){|server, port|
      ctx = OpenSSL::SSL::SSLContext.new
      client_ca_from_server = nil
      ctx.client_cert_cb = Proc.new do |sslconn|
        client_ca_from_server = sslconn.client_ca
        [@cli_cert, @cli_key]
      end
      server_connect(port, ctx) { |ssl| assert_equal([@ca], client_ca_from_server) }
    }
  end

  def test_starttls
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, false){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      ssl.sync_close = true
      str = "x" * 1000 + "\n"

      OpenSSL::TestUtils.silent do
        ITERATIONS.times{
          ssl.puts(str)
          assert_equal(str, ssl.gets)
        }
        starttls(ssl)
      end

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

  def test_exception_in_verify_callback_is_ignored
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params(
        :verify_callback => Proc.new do |preverify_ok, store_ctx|
          store_ctx.error = OpenSSL::X509::V_OK
          raise RuntimeError
        end
      )
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      OpenSSL::TestUtils.silent do
        # SSLError, not RuntimeError
        assert_raise(OpenSSL::SSL::SSLError) { ssl.connect }
      end
      assert_equal(OpenSSL::X509::V_ERR_CERT_REJECTED, ssl.verify_result)
      ssl.close
    }
  end

  def test_sslctx_set_params
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
      sock = TCPSocket.new("127.0.0.1", port)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.set_params
      assert_equal(OpenSSL::SSL::VERIFY_PEER, ctx.verify_mode)
      assert_equal(TLS_DEFAULT_OPS, ctx.options)
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
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
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
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
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

    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, :ctx_proc => ctx_proc, :server_proc => server_proc) do |server, port|
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
      start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, :server_proc => server_proc){|server, port|
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
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true, :ctx_proc => ctx_proc){|server, port|
      server_connect(port) { |ssl|
        ssl.puts('hello')
        assert_equal("hello\n", ssl.gets)
      }
    }
  end

  # different OpenSSL versions react differently when facing a SSL/TLS version
  # that has been marked as forbidden, therefore either of these may be raised
  HANDSHAKE_ERRORS = [OpenSSL::SSL::SSLError, Errno::ECONNRESET]

if OpenSSL::SSL::SSLContext::METHODS.include? :TLSv1

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

if OpenSSL::OPENSSL_VERSION_NUMBER > 0x10001000

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
      start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
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
    start_server(PORT, OpenSSL::SSL::VERIFY_NONE, true){|server, port|
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

  private

  def start_server_version(version, ctx_proc=nil, server_proc=nil, &blk)
    ctx_wrap = Proc.new { |ctx|
      ctx.ssl_version = version
      ctx_proc.call(ctx) if ctx_proc
    }
    start_server(
      PORT,
      OpenSSL::SSL::VERIFY_NONE,
      true,
      :ctx_proc => ctx_wrap,
      :server_proc => server_proc,
      &blk
    )
  end

  def server_connect(port, ctx=nil)
    sock = TCPSocket.new("127.0.0.1", port)
    ssl = ctx ? OpenSSL::SSL::SSLSocket.new(sock, ctx) : OpenSSL::SSL::SSLSocket.new(sock)
    ssl.sync_close = true
    ssl.connect
    yield ssl
  ensure
    ssl.close
  end
end

end
