# frozen_string_literal: true
require 'test/unit'
require 'socket'
require_relative 'scheduler'

class TestIOScheduler < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read
    return unless defined?(UNIXSocket)

    message = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      i, o = UNIXSocket.pair

      Fiber do
        message = i.read(20)
        i.close
      end

      Fiber do
        o.write("Hello World")
        o.close
      end
    end

    thread.join

    assert_equal MESSAGE, message
  end

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

  def test_mutex
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber do
        assert_equal Thread.scheduler, scheduler

        mutex.synchronize do
          assert_nil Thread.scheduler
        end
      end
    end

    thread.join
  end

  def test_blocking
    scheduler = Scheduler.new

    thread = Thread.new do
      Thread.current.scheduler = scheduler

      # Close is always a blocking operation.
      IO.pipe.each(&:close)
    end

    thread.join

    assert_not_empty scheduler.blocking
    assert_match /test_scheduler.rb:\d+:in `close'/, scheduler.blocking.last
  end
end
