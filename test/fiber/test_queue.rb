# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberQueue < Test::Unit::TestCase
  def test_pop_with_timeout
    queue = Thread::Queue.new
    kill = false
    result = :unspecified

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler(scheduler)

      Fiber.schedule do
        result = queue.pop(timeout: 0.0001)
      end

      scheduler.run
    end
    until thread.join(2)
      kill = true
      thread.kill
    end

    assert_false(kill, 'Getting stuck due to a possible compiler bug.')
    assert_nil result
  end

  def test_pop_with_timeout_and_value
    queue = Thread::Queue.new
    queue.push(:something)
    kill = false
    result = :unspecified

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler(scheduler)

      Fiber.schedule do
        result = queue.pop(timeout: 0.0001)
      end

      scheduler.run
    end
    until thread.join(2)
      kill = true
      thread.kill
    end

    assert_false(kill, 'Getting stuck due to a possible compiler bug.')
    assert_equal :something, result
  end
end
