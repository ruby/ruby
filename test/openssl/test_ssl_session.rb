require_relative "utils"

if defined?(OpenSSL)

class OpenSSL::TestSSLSession < OpenSSL::SSLTestCase
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
end

end
