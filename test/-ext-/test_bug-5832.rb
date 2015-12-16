# frozen_string_literal: false
require '-test-/bug-5832/bug'

class Test_BUG_5832 < Test::Unit::TestCase
  def test_block_passing
    bug5832 = '[ruby-dev:45071]'

    c = Class.new do
      define_method(:call_invoke_block_from_c) do
        Bug.funcall_callback(self)
      end

      def callback
        yield if block_given?
      end
    end

    assert_nothing_raised(RuntimeError, bug5832) do
      c.new.call_invoke_block_from_c { raise 'unreachable' }
    end
  end
end
