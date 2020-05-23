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
        Fiber do
          sleep(i/100.0)
          items << i
        end
      end

      # Should be 5 fibers waiting:
      assert_equal scheduler.waiting.size, 5
    end

    thread.join

    assert_equal ITEMS, items
  end
end
