# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberSleep < Test::Unit::TestCase
  ITEMS = [0, 1, 2, 3, 4]

  def test_sleep
    items = []

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      5.times do |i|
        Fiber.schedule do
          assert_operator sleep(i/100.0), :>=, 0
          items << i
        end
      end

      # Should be 5 fibers waiting:
      assert_equal scheduler.waiting.size, 5
    end

    thread.join

    assert_equal ITEMS, items
  end

  def test_sleep_returns_seconds_slept
    seconds = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler
      Fiber.schedule do
        seconds = sleep(2)
      end
    end

    thread.join

    assert_operator seconds, :>=, 2, "actual: %p" % seconds
  end

  def test_broken_sleep
    thread = Thread.new do
      Thread.current.report_on_exception = false

      scheduler = Scheduler.new

      def scheduler.kernel_sleep(duration = nil)
        raise "Broken sleep!"
      end

      Fiber.set_scheduler scheduler

      Fiber.schedule do
        sleep 0
      end

    ensure
      scheduler.close
    end

    assert_raise(RuntimeError) do
      thread.join
    end
  end
end
