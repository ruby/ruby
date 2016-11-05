# frozen_string_literal: false
require 'net/smtp'
require 'stringio'
require 'test/unit'

module Net
  class TestSMTP < Test::Unit::TestCase
    CA_FILE = File.expand_path("../imap/cacert.pem", __dir__)
    SERVER_KEY = File.expand_path("../imap/server.key", __dir__)
    SERVER_CERT = File.expand_path("../imap/server.crt", __dir__)

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
      server = TCPServer.new("127.0.0.1", 0)
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ca_file = CA_FILE
      ctx.key = File.open(SERVER_KEY) { |f|
        OpenSSL::PKey::RSA.new(f)
      }
      ctx.cert = File.open(SERVER_CERT) { |f|
        OpenSSL::X509::Certificate.new(f)
      }
      ssl_server = OpenSSL::SSL::SSLServer.new(server, ctx)
      begin
        sock = nil
        Thread.start do
          sock = ssl_server.accept
          sock.write("220 localhost Service ready\r\n")
          sock.gets
          sock.write("250 localhost\r\n")
          sock.gets
          sock.write("221 localhost Service closing transmission channel\r\n")
        end
        smtp = Net::SMTP.new("localhost", server.addr[1])
        smtp.enable_tls
        smtp.open_timeout = 0.1
        smtp.start do
        end
      ensure
        sock.close if sock
        ssl_server.close
      end
    end

    def test_tls_connect_timeout
      server = TCPServer.new("127.0.0.1", 0)
      begin
        sock = nil
        Thread.start do
          sock = server.accept
        end
        smtp = Net::SMTP.new("127.0.0.1", server.addr[1])
        smtp.enable_tls
        smtp.open_timeout = 0.1
        assert_raise(Net::OpenTimeout) do
          smtp.start do
          end
        end
      ensure
        sock.close if sock
        server.close
      end
    end
  end
end
