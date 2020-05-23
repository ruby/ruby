# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberMutex < Test::Unit::TestCase
  def test_mutex_synchronize
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

  def test_mutex_deadlock
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber do
        assert_equal Thread.scheduler, scheduler

        mutex.synchronize do
          Fiber.yield
        end
      end

      assert_raise ThreadError do
        mutex.lock
      end
    end

    thread.join
  end
end
