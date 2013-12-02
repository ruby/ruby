require 'net/smtp'
require 'stringio'
require 'minitest/autorun'

module Net
  class TestSMTP < MiniTest::Unit::TestCase
    class FakeSocket
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

      assert_raises RuntimeError do
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
  end
end
