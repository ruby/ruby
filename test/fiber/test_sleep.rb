# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberSleep < Test::Unit::TestCase
  ITEMS = [0, 1, 2, 3, 4]

  def test_sleep
    items = []

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

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
      Thread.current.scheduler = scheduler
      Fiber.schedule do
        seconds = sleep(2)
      end
    end

    thread.join

    assert_operator seconds, :>=, 2, "actual: %p" % seconds
  end
end
