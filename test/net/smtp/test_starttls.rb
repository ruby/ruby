require 'net/smtp'
require 'test/unit'

module Net
  class TestStarttls < Test::Unit::TestCase
    class MySMTP < SMTP
      def initialize(socket)
        @fake_socket = socket
        super("smtp.example.com")
      end

      def tcp_socket(*)
        @fake_socket
      end

      def tlsconnect(*)
        @fake_socket
      end
    end

    def teardown
      @server_thread&.exit
      @server_socket&.close
      @client_socket&.close
    end

    def start_smtpd(starttls)
      @server_socket, @client_socket = Object.const_defined?(:UNIXSocket) ?
        UNIXSocket.pair : Socket.pair(:INET, :STREAM, 0)
      @starttls_executed = false
      @server_thread = Thread.new(@server_socket) do |s|
        s.puts "220 fakeserver\r\n"
        while cmd = s.gets&.chomp
          case cmd
          when /\AEHLO /
            s.puts "250-fakeserver\r\n"
            s.puts "250-STARTTLS\r\n" if starttls
            s.puts "250 8BITMIME\r\n"
          when /\ASTARTTLS/
            @starttls_executed = true
            s.puts "220 2.0.0 Ready to start TLS\r\n"
          else
            raise "unsupported command: #{cmd}"
          end
        end
      end
      @client_socket
    end

    def test_default_with_starttls_capable
      smtp = MySMTP.new(start_smtpd(true))
      smtp.start
      assert(@starttls_executed)
    end

    def test_default_without_starttls_capable
      smtp = MySMTP.new(start_smtpd(false))
      smtp.start
      assert(!@starttls_executed)
    end

    def test_enable_starttls_with_starttls_capable
      smtp = MySMTP.new(start_smtpd(true))
      smtp.enable_starttls
      smtp.start
      assert(@starttls_executed)
    end

    def test_enable_starttls_without_starttls_capable
      smtp = MySMTP.new(start_smtpd(false))
      smtp.enable_starttls
      err = assert_raise(Net::SMTPUnsupportedCommand) { smtp.start }
      assert_equal("STARTTLS is not supported on this server", err.message)
    end

    def test_enable_starttls_auto_with_starttls_capable
      smtp = MySMTP.new(start_smtpd(true))
      smtp.enable_starttls_auto
      smtp.start
      assert(@starttls_executed)
    end

    def test_tls_with_starttls_capable
      smtp = MySMTP.new(start_smtpd(true))
      smtp.enable_tls
      smtp.start
      assert(!@starttls_executed)
    end

    def test_tls_without_starttls_capable
      smtp = MySMTP.new(start_smtpd(false))
      smtp.enable_tls
    end

    def test_disable_starttls
      smtp = MySMTP.new(start_smtpd(true))
      smtp.disable_starttls
      smtp.start
      assert(!@starttls_executed)
    end

    def test_enable_tls_and_enable_starttls
      smtp = MySMTP.new(start_smtpd(true))
      smtp.enable_tls
      err = assert_raise(ArgumentError) { smtp.enable_starttls }
      assert_equal("SMTPS and STARTTLS is exclusive", err.message)
    end

    def test_enable_tls_and_enable_starttls_auto
      smtp = MySMTP.new(start_smtpd(true))
      smtp.enable_tls
      err = assert_raise(ArgumentError) { smtp.enable_starttls_auto }
      assert_equal("SMTPS and STARTTLS is exclusive", err.message)
    end

    def test_enable_starttls_and_enable_starttls_auto
      smtp = MySMTP.new(start_smtpd(true))
      smtp.enable_starttls
      assert_nothing_raised { smtp.enable_starttls_auto }
    end
  end
end
