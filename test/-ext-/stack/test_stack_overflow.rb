# frozen_string_literal: true
require 'test/unit'

class Test_StackOverflow < Test::Unit::TestCase
  def test_proc_overflow
    assert_separately([], <<~RUBY)
      require '-test-/stack'

      assert_raise(SystemStackError) do
        Thread.alloca_overflow
      end
    RUBY
  end

  def test_thread_stack_overflow
    assert_separately([], <<~RUBY)
      require '-test-/stack'

      thread = Thread.new do
        Thread.current.report_on_exception = false
        Thread.alloca_overflow
      end

      assert_raise(SystemStackError) do
        thread.join
      end
    RUBY
  end

  def test_fiber_stack_overflow
    assert_separately([], <<~RUBY)
      require '-test-/stack'

      fiber = Fiber.new do
        Thread.alloca_overflow
      end

      assert_raise(SystemStackError) do
        fiber.resume
      end
    RUBY
  end
end
