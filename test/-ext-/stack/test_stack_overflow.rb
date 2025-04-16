# frozen_string_literal: true
require 'test/unit'
require '-test-/stack'

class Test_StackOverflow < Test::Unit::TestCase
  # def test_proc_overflow
  #   overflow_proc = proc do
  #     Thread.alloca_overflow
  #   end

  #   assert_raise(SystemStackError) do
  #     overflow_proc.call
  #   end
  # end

  def test_thread_stack_overflow
    thread = Thread.new do
      Thread.current.report_on_exception = false

      Thread.alloca_overflow
    end

    assert_raise(SystemStackError) do
      thread.join
    end
  end

  def test_fiber_stack_overflow
    fiber = Fiber.new do
      Thread.alloca_overflow
    end

    assert_raise(SystemStackError) do
      fiber.resume
    end
  end
end
