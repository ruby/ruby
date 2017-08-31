# frozen_string_literal: true
require 'net/smtp'
require 'stringio'
require 'test/unit'

module Net
  class TestSMTP < Test::Unit::TestCase
    CA_FILE = File.expand_path("../fixtures/cacert.pem", __dir__)
    SERVER_KEY = File.expand_path("../fixtures/server.key", __dir__)
    SERVER_CERT = File.expand_path("../fixtures/server.crt", __dir__)

    class FakeSocket
      attr_reader :write_io

      def initialize out = "250 OK\n"
        @write_io = StringIO.new
        @read_io  = StringIO.new out
      end

      def writeline line
        @write_io.write "#{line}\r\n"
      end

      def readline
        line = @read_io.gets
        raise 'ran out of input' unless line
        line.chop
      end
    end

    def test_critical
      smtp = Net::SMTP.new 'localhost', 25

      assert_raise RuntimeError do
        smtp.send :critical do
          raise 'fail on purpose'
        end
      end

      assert_kind_of Net::SMTP::Response, smtp.send(:critical),
                     '[Bug #9125]'
    end

    def test_esmtp
      smtp = Net::SMTP.new 'localhost', 25
      assert smtp.esmtp
      assert smtp.esmtp?

      smtp.esmtp = 'omg'
      assert_equal 'omg', smtp.esmtp
      assert_equal 'omg', smtp.esmtp?
    end

    def test_rset
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, FakeSocket.new

      assert smtp.rset
    end

    def test_mailfrom
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      assert smtp.mailfrom("foo@example.com").success?
      assert_equal "MAIL FROM:<foo@example.com>\r\n", sock.write_io.string
    end

    def test_rcptto
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      assert smtp.rcptto("foo@example.com").success?
      assert_equal "RCPT TO:<foo@example.com>\r\n", sock.write_io.string
    end

    def test_auth_plain
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      assert smtp.auth_plain("foo", "bar").success?
      assert_equal "AUTH PLAIN AGZvbwBiYXI=\r\n", sock.write_io.string
    end

    def test_crlf_injection
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, FakeSocket.new

      assert_raise(ArgumentError) do
        smtp.mailfrom("foo\r\nbar")
      end

      assert_raise(ArgumentError) do
        smtp.mailfrom("foo\rbar")
      end

      assert_raise(ArgumentError) do
        smtp.mailfrom("foo\nbar")
      end

      assert_raise(ArgumentError) do
        smtp.rcptto("foo\r\nbar")
      end
    end

    def test_tls_connect
      servers = Socket.tcp_server_sockets("localhost", 0)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ca_file = CA_FILE
      ctx.key = File.open(SERVER_KEY) { |f|
        OpenSSL::PKey::RSA.new(f)
      }
      ctx.cert = File.open(SERVER_CERT) { |f|
        OpenSSL::X509::Certificate.new(f)
      }
      begin
        sock = nil
        Thread.start do
          s = accept(servers)
          sock = OpenSSL::SSL::SSLSocket.new(s, ctx)
          sock.sync_close = true
          sock.accept
          sock.write("220 localhost Service ready\r\n")
          sock.gets
          sock.write("250 localhost\r\n")
          sock.gets
          sock.write("221 localhost Service closing transmission channel\r\n")
        end
        smtp = Net::SMTP.new("localhost", servers[0].local_address.ip_port)
        smtp.enable_tls
        smtp.open_timeout = 1
        smtp.start do
        end
      ensure
        sock.close if sock
        servers.each(&:close)
      end
    rescue LoadError
      # skip (require openssl)
    end

    def test_tls_connect_timeout
      servers = Socket.tcp_server_sockets("localhost", 0)
      begin
        sock = nil
        Thread.start do
          sock = accept(servers)
        end
        smtp = Net::SMTP.new("localhost", servers[0].local_address.ip_port)
        smtp.enable_tls
        smtp.open_timeout = 0.1
        assert_raise(Net::OpenTimeout) do
          smtp.start do
          end
        end
      rescue LoadError
        # skip (require openssl)
      ensure
        sock.close if sock
        servers.each(&:close)
      end
    end

    def test_eof_error_backtrace
      bug13018 = '[ruby-core:78550] [Bug #13018]'
      servers = Socket.tcp_server_sockets("localhost", 0)
      begin
        sock = nil
        t = Thread.start do
          sock = accept(servers)
          sock.close
        end
        smtp = Net::SMTP.new("localhost", servers[0].local_address.ip_port)
        e = assert_raise(EOFError, bug13018) do
          smtp.start do
          end
        end
        assert_equal(EOFError, e.class, bug13018)
        assert(e.backtrace.grep(%r"\bnet/smtp\.rb:").size > 0, bug13018)
      ensure
        sock.close if sock
        servers.each(&:close)
        t.join
      end
    end

    private

    def accept(servers)
      loop do
        readable, = IO.select(servers.map(&:to_io))
        readable.each do |r|
          sock, addr = r.accept_nonblock(exception: false)
          next if sock == :wait_readable
          return sock
        end
      end
    end
  end
end
