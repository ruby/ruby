# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestSSLSession < OpenSSL::SSLTestCase
  def test_session
    pend "TLS 1.2 is not supported" unless tls12_supported?

    ctx_proc = proc { |ctx| ctx.ssl_version = :TLSv1_2 }
    start_server(ctx_proc: ctx_proc) do |port|
      server_connect_with_session(port, nil, nil) { |ssl|
        session = ssl.session
        assert(session == OpenSSL::SSL::Session.new(session.to_pem))
        assert(session == OpenSSL::SSL::Session.new(ssl))
        session.timeout = 5
        assert_equal(5, session.timeout)
        assert_not_nil(session.time)
        # SSL_SESSION_time keeps long value so we can't keep nsec fragment.
        session.time = t1 = Time.now.to_i
        assert_equal(Time.at(t1), session.time)
        assert_not_nil(session.id)
        pem = session.to_pem
        assert_match(/\A-----BEGIN SSL SESSION PARAMETERS-----/, pem)
        assert_match(/-----END SSL SESSION PARAMETERS-----\Z/, pem)
        pem.gsub!(/-----(BEGIN|END) SSL SESSION PARAMETERS-----/, '').gsub!(/[\r\n]+/m, '')
        assert_equal(session.to_der, pem.unpack('m*')[0])
        assert_not_nil(session.to_text)
      }
    end
  end

  DUMMY_SESSION = <<__EOS__
-----BEGIN SSL SESSION PARAMETERS-----
MIIDzQIBAQICAwEEAgA5BCAF219w9ZEV8dNA60cpEGOI34hJtIFbf3bkfzSgMyad
MQQwyGLbkCxE4OiMLdKKem+pyh8V7ifoP7tCxhdmwoDlJxI1v6nVCjai+FGYuncy
NNSWoQYCBE4DDWuiAwIBCqOCAo4wggKKMIIBcqADAgECAgECMA0GCSqGSIb3DQEB
BQUAMD0xEzARBgoJkiaJk/IsZAEZFgNvcmcxGTAXBgoJkiaJk/IsZAEZFglydWJ5
LWxhbmcxCzAJBgNVBAMMAkNBMB4XDTExMDYyMzA5NTQ1MVoXDTExMDYyMzEwMjQ1
MVowRDETMBEGCgmSJomT8ixkARkWA29yZzEZMBcGCgmSJomT8ixkARkWCXJ1Ynkt
bGFuZzESMBAGA1UEAwwJbG9jYWxob3N0MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCB
iQKBgQDLwsSw1ECnPtT+PkOgHhcGA71nwC2/nL85VBGnRqDxOqjVh7CxaKPERYHs
k4BPCkE3brtThPWc9kjHEQQ7uf9Y1rbCz0layNqHyywQEVLFmp1cpIt/Q3geLv8Z
D9pihowKJDyMDiN6ArYUmZczvW4976MU3+l54E6lF/JfFEU5hwIDAQABoxIwEDAO
BgNVHQ8BAf8EBAMCBaAwDQYJKoZIhvcNAQEFBQADggEBACj5WhoZ/ODVeHpwgq1d
8fW/13ICRYHYpv6dzlWihyqclGxbKMlMnaVCPz+4JaVtMz3QB748KJQgL3Llg3R1
ek+f+n1MBCMfFFsQXJ2gtLB84zD6UCz8aaCWN5/czJCd7xMz7fRLy3TOIW5boXAU
zIa8EODk+477K1uznHm286ab0Clv+9d304hwmBZgkzLg6+31Of6d6s0E0rwLGiS2
sOWYg34Y3r4j8BS9Ak4jzpoLY6cJ0QAKCOJCgmjGr4XHpyXMLbicp3ga1uSbwtVO
gF/gTfpLhJC+y0EQ5x3Ftl88Cq7ZJuLBDMo/TLIfReJMQu/HlrTT7+LwtneSWGmr
KkSkAgQApQMCAROqgcMEgcAuDkAVfj6QAJMz9yqTzW5wPFyty7CxUEcwKjUqj5UP
/Yvky1EkRuM/eQfN7ucY+MUvMqv+R8ZSkHPsnjkBN5ChvZXjrUSZKFVjR4eFVz2V
jismLEJvIFhQh6pqTroRrOjMfTaM5Lwoytr2FTGobN9rnjIRsXeFQW1HLFbXn7Dh
8uaQkMwIVVSGRB8T7t6z6WIdWruOjCZ6G5ASI5XoqAHwGezhLodZuvJEfsVyCF9y
j+RBGfCFrrQbBdnkFI/ztgM=
-----END SSL SESSION PARAMETERS-----
__EOS__

  DUMMY_SESSION_NO_EXT = <<-__EOS__
-----BEGIN SSL SESSION PARAMETERS-----
MIIDCAIBAQICAwAEAgA5BCDyAW7rcpzMjDSosH+Tv6sukymeqgq3xQVVMez628A+
lAQw9TrKzrIqlHEh6ltuQaqv/Aq83AmaAlogYktZgXAjOGnhX7ifJDNLMuCfQq53
hPAaoQYCBE4iDeeiBAICASyjggKOMIICijCCAXKgAwIBAgIBAjANBgkqhkiG9w0B
AQUFADA9MRMwEQYKCZImiZPyLGQBGRYDb3JnMRkwFwYKCZImiZPyLGQBGRYJcnVi
eS1sYW5nMQswCQYDVQQDDAJDQTAeFw0xMTA3MTYyMjE3MTFaFw0xMTA3MTYyMjQ3
MTFaMEQxEzARBgoJkiaJk/IsZAEZFgNvcmcxGTAXBgoJkiaJk/IsZAEZFglydWJ5
LWxhbmcxEjAQBgNVBAMMCWxvY2FsaG9zdDCBnzANBgkqhkiG9w0BAQEFAAOBjQAw
gYkCgYEAy8LEsNRApz7U/j5DoB4XBgO9Z8Atv5y/OVQRp0ag8Tqo1YewsWijxEWB
7JOATwpBN267U4T1nPZIxxEEO7n/WNa2ws9JWsjah8ssEBFSxZqdXKSLf0N4Hi7/
GQ/aYoaMCiQ8jA4jegK2FJmXM71uPe+jFN/peeBOpRfyXxRFOYcCAwEAAaMSMBAw
DgYDVR0PAQH/BAQDAgWgMA0GCSqGSIb3DQEBBQUAA4IBAQA3TRzABRG3kz8jEEYr
tDQqXgsxwTsLhTT5d1yF0D8uFw+y15hJAJnh6GJHjqhWBrF4zNoTApFo+4iIL6g3
q9C3mUsxIVAHx41DwZBh/FI7J4FqlAoGOguu7892CNVY3ZZjc3AXMTdKjcNoWPzz
FCdj5fNT24JMMe+ZdGZK97ChahJsdn/6B3j6ze9NK9mfYEbiJhejGTPLOFVHJCGR
KYYZ3ZcKhLDr9ql4d7cCo1gBtemrmFQGPui7GttNEqmXqUKvV8mYoa8farf5i7T4
L6a/gp2cVZTaDIS1HjbJsA/Ag7AajZqiN6LfqShNUVsrMZ+5CoV8EkBDTZPJ9MSr
a3EqpAIEAKUDAgET
-----END SSL SESSION PARAMETERS-----
__EOS__


  def test_session_time
    sess = OpenSSL::SSL::Session.new(DUMMY_SESSION_NO_EXT)
    sess.time = (now = Time.now)
    assert_equal(now.to_i, sess.time.to_i)
    sess.time = 1
    assert_equal(1, sess.time.to_i)
    sess.time = 1.2345
    assert_equal(1, sess.time.to_i)
    # Can OpenSSL handle t>2038y correctly? Version?
    sess.time = 2**31 - 1
    assert_equal(2**31 - 1, sess.time.to_i)
  end

  def test_session_timeout
    sess = OpenSSL::SSL::Session.new(DUMMY_SESSION_NO_EXT)
    assert_raise(TypeError) do
      sess.timeout = Time.now
    end
    sess.timeout = 1
    assert_equal(1, sess.timeout.to_i)
    sess.timeout = 1.2345
    assert_equal(1, sess.timeout.to_i)
    sess.timeout = 2**31 - 1
    assert_equal(2**31 - 1, sess.timeout.to_i)
  end

  def test_session_exts_read
    assert(OpenSSL::SSL::Session.new(DUMMY_SESSION))
  end

  def test_resumption
    non_resumable = nil
    start_server { |port|
      server_connect_with_session(port, nil, nil) { |ssl|
        non_resumable = ssl.session
      }
    }

    ctx_proc = proc { |ctx|
      ctx.options &= ~OpenSSL::SSL::OP_NO_TICKET
      # Disable server-side session cache which is enabled by default
      ctx.session_cache_mode = OpenSSL::SSL::SSLContext::SESSION_CACHE_OFF
    }
    start_server(ctx_proc: ctx_proc) do |port|
      sess1 = server_connect_with_session(port, nil, nil) { |ssl|
        ssl.puts("abc"); assert_equal "abc\n", ssl.gets
        assert_equal false, ssl.session_reused?
        ssl.session
      }

      server_connect_with_session(port, nil, non_resumable) { |ssl|
        ssl.puts("abc"); assert_equal "abc\n", ssl.gets
        assert_equal false, ssl.session_reused?
      }

      server_connect_with_session(port, nil, sess1) { |ssl|
        ssl.puts("abc"); assert_equal "abc\n", ssl.gets
        assert_equal true, ssl.session_reused?
      }
    end
  end

  def test_server_session_cache
    pend "TLS 1.2 is not supported" unless tls12_supported?

    ctx_proc = Proc.new do |ctx|
      ctx.ssl_version = :TLSv1_2
      ctx.options |= OpenSSL::SSL::OP_NO_TICKET
    end

    connections = nil
    saved_session = nil
    server_proc = Proc.new do |ctx, ssl|
      stats = ctx.session_cache_stats

      case connections
      when 0
        assert_equal false, ssl.session_reused?
        assert_equal 1, stats[:cache_num]
        assert_equal 0, stats[:cache_hits]
        assert_equal 0, stats[:cache_misses]
      when 1
        assert_equal true, ssl.session_reused?
        assert_equal 1, stats[:cache_num]
        assert_equal 1, stats[:cache_hits]
        assert_equal 0, stats[:cache_misses]

        saved_session = ssl.session
        assert_equal true, ctx.session_remove(ssl.session)
      when 2
        assert_equal false, ssl.session_reused?
        assert_equal 1, stats[:cache_num]
        assert_equal 1, stats[:cache_hits]
        assert_equal 1, stats[:cache_misses]

        assert_equal true, ctx.session_add(saved_session.dup)
      when 3
        assert_equal true, ssl.session_reused?
        assert_equal 2, stats[:cache_num]
        assert_equal 2, stats[:cache_hits]
        assert_equal 1, stats[:cache_misses]

        ctx.flush_sessions(Time.now + 10000)
      when 4
        assert_equal false, ssl.session_reused?
        assert_equal 1, stats[:cache_num]
        assert_equal 2, stats[:cache_hits]
        assert_equal 2, stats[:cache_misses]

        assert_equal true, ctx.session_add(saved_session.dup)
      end

      readwrite_loop(ctx, ssl)
    end

    start_server(ctx_proc: ctx_proc, server_proc: server_proc) do |port|
      first_session = nil
      10.times do |i|
        connections = i
        server_connect_with_session(port, nil, first_session) { |ssl|
          ssl.puts("abc"); assert_equal "abc\n", ssl.gets
          first_session ||= ssl.session

          case connections
          when 0;
          when 1; assert_equal true, ssl.session_reused?
          when 2; assert_equal false, ssl.session_reused?
          when 3; assert_equal true, ssl.session_reused?
          when 4; assert_equal false, ssl.session_reused?
          when 5..9; assert_equal true, ssl.session_reused?
          end
        }
      end
    end
  end

  # Skipping tests that use session_remove_cb by default because it may cause
  # deadlock.
  TEST_SESSION_REMOVE_CB = ENV["OSSL_TEST_ALL"] == "1"

  def test_ctx_client_session_cb
    pend "TLS 1.2 is not supported" unless tls12_supported?

    ctx_proc = proc { |ctx| ctx.ssl_version = :TLSv1_2 }
    start_server(ctx_proc: ctx_proc) do |port|
      called = {}
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.session_cache_mode = OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT
      ctx.session_new_cb = lambda { |ary|
        sock, sess = ary
        called[:new] = [sock, sess]
      }
      if TEST_SESSION_REMOVE_CB
        ctx.session_remove_cb = lambda { |ary|
          ctx, sess = ary
          called[:remove] = [ctx, sess]
          # any resulting value is OK (ignored)
        }
      end

      server_connect_with_session(port, ctx, nil) { |ssl|
        assert_equal(1, ctx.session_cache_stats[:cache_num])
        assert_equal(1, ctx.session_cache_stats[:connect_good])
        assert_equal([ssl, ssl.session], called[:new])
        assert(ctx.session_remove(ssl.session))
        assert(!ctx.session_remove(ssl.session))
        if TEST_SESSION_REMOVE_CB
          assert_equal([ctx, ssl.session], called[:remove])
        end
      }
    end
  end

  def test_ctx_server_session_cb
    pend "TLS 1.2 is not supported" unless tls12_supported?

    connections = nil
    called = {}
    sctx = nil
    ctx_proc = Proc.new { |ctx|
      sctx = ctx
      ctx.ssl_version = :TLSv1_2
      ctx.options |= OpenSSL::SSL::OP_NO_TICKET

      # get_cb is called whenever a client proposed to resume a session but
      # the session could not be found in the internal session cache.
      last_server_session = nil
      ctx.session_get_cb = lambda { |ary|
        _sess, data = ary
        called[:get] = data

        if connections == 2
          last_server_session.dup
        else
          nil
        end
      }

      ctx.session_new_cb = lambda { |ary|
        _sock, sess = ary
        called[:new] = sess
        last_server_session = sess
      }

      if TEST_SESSION_REMOVE_CB
        ctx.session_remove_cb = lambda { |ary|
          _ctx, sess = ary
          called[:remove] = sess
        }
      end
    }
    start_server(ctx_proc: ctx_proc) do |port|
      connections = 0
      sess0 = server_connect_with_session(port, nil, nil) { |ssl|
        ssl.puts("abc"); assert_equal "abc\n", ssl.gets
        assert_equal false, ssl.session_reused?
        ssl.session
      }
      assert_nil called[:get]
      assert_not_nil called[:new]
      assert_equal sess0.id, called[:new].id
      if TEST_SESSION_REMOVE_CB
        assert_nil called[:remove]
      end
      called.clear

      # Internal cache hit
      connections = 1
      server_connect_with_session(port, nil, sess0.dup) { |ssl|
        ssl.puts("abc"); assert_equal "abc\n", ssl.gets
        assert_equal true, ssl.session_reused?
        ssl.session
      }
      assert_nil called[:get]
      assert_nil called[:new]
      if TEST_SESSION_REMOVE_CB
        assert_nil called[:remove]
      end
      called.clear

      sctx.flush_sessions(Time.now + 10000)
      if TEST_SESSION_REMOVE_CB
        assert_not_nil called[:remove]
        assert_equal sess0.id, called[:remove].id
      end
      called.clear

      # External cache hit
      connections = 2
      sess2 = server_connect_with_session(port, nil, sess0.dup) { |ssl|
        ssl.puts("abc"); assert_equal "abc\n", ssl.gets
        if !ssl.session_reused? && openssl?(1, 1, 0) && !openssl?(1, 1, 0, 7)
          # OpenSSL >= 1.1.0, < 1.1.0g
          pend "External session cache is not working; " \
            "see https://github.com/openssl/openssl/pull/4014"
        end
        assert_equal true, ssl.session_reused?
        ssl.session
      }
      assert_equal sess0.id, sess2.id
      assert_equal sess0.id, called[:get]
      assert_nil called[:new]
      if TEST_SESSION_REMOVE_CB
        assert_nil called[:remove]
      end
      called.clear

      sctx.flush_sessions(Time.now + 10000)
      if TEST_SESSION_REMOVE_CB
        assert_not_nil called[:remove]
        assert_equal sess0.id, called[:remove].id
      end
      called.clear

      # Cache miss
      connections = 3
      sess3 = server_connect_with_session(port, nil, sess0.dup) { |ssl|
        ssl.puts("abc"); assert_equal "abc\n", ssl.gets
        assert_equal false, ssl.session_reused?
        ssl.session
      }
      assert_not_equal sess0.id, sess3.id
      assert_equal sess0.id, called[:get]
      assert_not_nil called[:new]
      assert_equal sess3.id, called[:new].id
      if TEST_SESSION_REMOVE_CB
        assert_nil called[:remove]
      end
    end
  end

  def test_dup
    sess_orig = OpenSSL::SSL::Session.new(DUMMY_SESSION)
    sess_dup = sess_orig.dup
    assert_equal(sess_orig.to_der, sess_dup.to_der)
  end

  private

  def server_connect_with_session(port, ctx = nil, sess = nil)
    sock = TCPSocket.new("127.0.0.1", port)
    ctx ||= OpenSSL::SSL::SSLContext.new
    ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
    ssl.session = sess if sess
    ssl.sync_close = true
    ssl.connect
    yield ssl if block_given?
  ensure
    ssl&.close
    sock&.close
  end
end

end
