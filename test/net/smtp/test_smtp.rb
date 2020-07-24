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
        line.chomp
      end

      def io
        @write_io
      end

      def write_message msg
        @write_io.write "#{msg.chomp}\r\n.\r\n"
      end

      def write_message_by_block &block
        block.call(@write_io)
        @write_io.write ".\r\n"
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

    def test_send_message
      sock = FakeSocket.new [
        "220 OK",        # MAIL FROM
        "250 OK",        # RCPT TO
        "354 Send data", # DATA
        "250 OK",
      ].join "\r\n"
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock

      smtp.send_message "Lorem ipsum", "foo@example.com", "bar@example.com"

      sock.write_io.rewind
      assert_equal "MAIL FROM:<foo@example.com>\r\n", sock.write_io.readline
      assert_equal "RCPT TO:<bar@example.com>\r\n", sock.write_io.readline
      assert_equal "DATA\r\n", sock.write_io.readline
      assert_equal "Lorem ipsum\r\n", sock.write_io.readline
      assert_equal ".\r\n", sock.write_io.readline
      assert sock.write_io.eof?
    end

    def test_send_message_params
      sock = FakeSocket.new [
        "220 OK",        # MAIL FROM
        "250 OK",        # RCPT TO
        "250 OK",        # RCPT TO
        "250 OK",        # RCPT TO
        "354 Send data", # DATA
        "250 OK",
      ].join "\r\n"
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock

      smtp.send_message "Lorem ipsum",
        ["foo@example.com", [:FOO]],
        ["1@example.com", ["2@example.com", ["FOO"]], ["3@example.com", {BAR: 1}]]

      sock.write_io.rewind
      assert_equal "MAIL FROM:<foo@example.com> FOO\r\n", sock.write_io.readline
      assert_equal "RCPT TO:<1@example.com>\r\n", sock.write_io.readline
      assert_equal "RCPT TO:<2@example.com> FOO\r\n", sock.write_io.readline
      assert_equal "RCPT TO:<3@example.com> BAR=1\r\n", sock.write_io.readline
      assert_equal "DATA\r\n", sock.write_io.readline
      assert_equal "Lorem ipsum\r\n", sock.write_io.readline
      assert_equal ".\r\n", sock.write_io.readline
      assert sock.write_io.eof?
    end

    def test_open_message_stream
      sock = FakeSocket.new [
        "220 OK",        # MAIL FROM
        "250 OK",        # RCPT TO
        "354 Send data", # DATA
        "250 OK",
      ].join "\r\n"
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock

      smtp.open_message_stream "foo@example.com", "bar@example.com" do |f|
        f.puts "Lorem ipsum"
      end

      sock.write_io.rewind
      assert_equal "MAIL FROM:<foo@example.com>\r\n", sock.write_io.readline
      assert_equal "RCPT TO:<bar@example.com>\r\n", sock.write_io.readline
      assert_equal "DATA\r\n", sock.write_io.readline
      assert_equal "Lorem ipsum\n", sock.write_io.readline
      assert_equal ".\r\n", sock.write_io.readline
      assert sock.write_io.eof?
    end

    def test_open_message_stream_params
      sock = FakeSocket.new [
        "220 OK",        # MAIL FROM
        "250 OK",        # RCPT TO
        "250 OK",        # RCPT TO
        "354 Send data", # DATA
        "250 OK",
      ].join "\r\n"
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock

      smtp.open_message_stream ["foo@example.com", [:FOO]], ["1@example.com", ["2@example.com", ["BAR"]]] do |f|
        f.puts "Lorem ipsum"
      end

      sock.write_io.rewind
      assert_equal "MAIL FROM:<foo@example.com> FOO\r\n", sock.write_io.readline
      assert_equal "RCPT TO:<1@example.com>\r\n", sock.write_io.readline
      assert_equal "RCPT TO:<2@example.com> BAR\r\n", sock.write_io.readline
      assert_equal "DATA\r\n", sock.write_io.readline
      assert_equal "Lorem ipsum\n", sock.write_io.readline
      assert_equal ".\r\n", sock.write_io.readline
      assert sock.write_io.eof?
    end

    def test_esmtp
      smtp = Net::SMTP.new 'localhost', 25
      assert smtp.esmtp
      assert smtp.esmtp?

      smtp.esmtp = 'omg'
      assert_equal 'omg', smtp.esmtp
      assert_equal 'omg', smtp.esmtp?
    end

    def test_helo
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock

      assert smtp.helo("example.com")
      assert_equal "HELO example.com\r\n", sock.write_io.string
    end

    def test_ehlo
      sock = FakeSocket.new [
        "220-smtp.example.com",
        "250-STARTTLS",
        "250-SIZE 100",
        "250 XFOO 1 2 3",
      ].join "\r\n"
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      res = smtp.ehlo("example.com")
      assert res.success?
      assert_equal ({"STARTTLS" => [], "SIZE" => ["100"], "XFOO" => ["1", "2", "3"]}), res.capabilities
      assert_equal "EHLO example.com\r\n", sock.write_io.string
    end

    def test_rset
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock

      assert smtp.rset
      assert_equal "RSET\r\n", sock.write_io.string
    end

    def test_mailfrom
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      assert smtp.mailfrom("foo@example.com").success?
      assert_equal "MAIL FROM:<foo@example.com>\r\n", sock.write_io.string
    end

    def test_mailfrom_params
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      assert smtp.mailfrom("foo@example.com", [:FOO]).success?
      assert_equal "MAIL FROM:<foo@example.com> FOO\r\n", sock.write_io.string
    end

    def test_rcptto
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      assert smtp.rcptto("foo@example.com").success?
      assert_equal "RCPT TO:<foo@example.com>\r\n", sock.write_io.string
    end

    def test_rcptto_params
      sock = FakeSocket.new
      smtp = Net::SMTP.new 'localhost', 25
      smtp.instance_variable_set :@socket, sock
      assert smtp.rcptto("foo@example.com", ["FOO"]).success?
      assert_equal "RCPT TO:<foo@example.com> FOO\r\n", sock.write_io.string
    end

    def test_addr_req
      smtp = Net::SMTP.new 'localhost', 25

      res = smtp.addr_req("MAIL FROM", "foo@example.com", [])
      assert_equal "MAIL FROM:<foo@example.com>", res

      res = smtp.addr_req("MAIL FROM", "foo@example.com", [:FOO, "BAR"])
      assert_equal "MAIL FROM:<foo@example.com> FOO BAR", res

      res = smtp.addr_req("MAIL FROM", "foo@example.com", {FOO: nil, BAR: "1"})
      assert_equal "MAIL FROM:<foo@example.com> FOO BAR=1", res
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
          sock, = r.accept_nonblock(exception: false)
          next if sock == :wait_readable
          return sock
        end
      end
    end
  end
end
