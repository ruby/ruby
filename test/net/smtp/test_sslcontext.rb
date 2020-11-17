require 'net/smtp'
require 'test/unit'

module Net
  class TestSSLContext < Test::Unit::TestCase
    class MySMTP < SMTP
      attr_reader :__ssl_context, :__tls_hostname

      def initialize(socket)
        @fake_socket = socket
        super("smtp.example.com")
      end

      def tcp_socket(*)
        @fake_socket
      end

      def ssl_socket_connect(*)
      end

      def tlsconnect(*)
        super
        @fake_socket
      end

      def ssl_socket(socket, context)
        @__ssl_context = context
        s = super
        hostname = @__tls_hostname = ''
        s.define_singleton_method(:post_connection_check){ |name| hostname.replace(name) }
        s
      end
    end

    def teardown
      @server_thread&.exit
      @server_socket&.close
      @client_socket&.close
    end

    def start_smtpd(starttls)
      @server_socket, @client_socket = UNIXSocket.pair
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

    def test_default
      smtp = MySMTP.new(start_smtpd(true))
      smtp.start
      assert_equal(OpenSSL::SSL::VERIFY_PEER, smtp.__ssl_context.verify_mode)
    end

    def test_enable_tls
      smtp = MySMTP.new(start_smtpd(true))
      context = OpenSSL::SSL::SSLContext.new
      smtp.enable_tls(context)
      smtp.start
      assert_equal(context, smtp.__ssl_context)
    end

    def test_enable_tls_before_disable_starttls
      smtp = MySMTP.new(start_smtpd(true))
      context = OpenSSL::SSL::SSLContext.new
      smtp.enable_tls(context)
      smtp.disable_starttls
      smtp.start
      assert_equal(context, smtp.__ssl_context)
    end

    def test_enable_starttls
      smtp = MySMTP.new(start_smtpd(true))
      context = OpenSSL::SSL::SSLContext.new
      smtp.enable_starttls(context)
      smtp.start
      assert_equal(context, smtp.__ssl_context)
    end

    def test_enable_starttls_before_disable_tls
      smtp = MySMTP.new(start_smtpd(true))
      context = OpenSSL::SSL::SSLContext.new
      smtp.enable_starttls(context)
      smtp.disable_tls
      smtp.start
      assert_equal(context, smtp.__ssl_context)
    end

    def test_start_with_tls_verify_true
      smtp = MySMTP.new(start_smtpd(true))
      smtp.start(tls_verify: true)
      assert_equal(OpenSSL::SSL::VERIFY_PEER, smtp.__ssl_context.verify_mode)
    end

    def test_start_with_tls_verify_false
      smtp = MySMTP.new(start_smtpd(true))
      smtp.start(tls_verify: false)
      assert_equal(OpenSSL::SSL::VERIFY_NONE, smtp.__ssl_context.verify_mode)
    end

    def test_start_with_tls_hostname
      smtp = MySMTP.new(start_smtpd(true))
      smtp.start(tls_hostname: "localhost")
      assert_equal("localhost", smtp.__tls_hostname)
    end

    def test_start_without_tls_hostname
      smtp = MySMTP.new(start_smtpd(true))
      smtp.start
      assert_equal("smtp.example.com", smtp.__tls_hostname)
    end

  end
end
