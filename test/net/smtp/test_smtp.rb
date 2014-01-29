require 'net/smtp'
require 'minitest/autorun'

module Net
  class TestSMTP < MiniTest::Unit::TestCase
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
  end
end
