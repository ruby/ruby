# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberQueue < Test::Unit::TestCase
  def test_pop_with_timeout
    queue = Thread::Queue.new
    result = :unspecified

    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler(scheduler)

      Fiber.schedule do
        result = queue.pop(timeout: 0.0001)
      end

      scheduler.run
    end.join

    assert_nil result
  end

  def test_pop_with_timeout_and_value
    queue = Thread::Queue.new
    queue.push(:something)
    result = :unspecified

    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler(scheduler)

      Fiber.schedule do
        result = queue.pop(timeout: 0.0001)
      end

      scheduler.run
    end.join

    assert_equal :something, result
  end
end
