# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberMutex < Test::Unit::TestCase
  def test_mutex_synchronize
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber.schedule do
        assert_equal Thread.scheduler, scheduler

        mutex.synchronize do
          assert Thread.scheduler
        end
      end
    end

    thread.join
  end

  def test_mutex_interleaved_locking
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber.schedule do
        mutex.lock
        sleep 0.1
        mutex.unlock
      end

      Fiber.schedule do
        mutex.lock
        sleep 0.1
        mutex.unlock
      end

      scheduler.run
    end

    thread.join
  end

  def test_condition_variable
    mutex = Mutex.new
    condition = ConditionVariable.new

    signalled = 0

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber.schedule do
        mutex.synchronize do
          3.times do
            condition.wait(mutex)
            signalled += 1
          end
        end
      end

      Fiber.schedule do
        3.times do
          mutex.synchronize do
            condition.signal
          end

          sleep 0.1
        end
      end

      scheduler.run
    end

    thread.join

    assert signalled > 1
  end

  def test_queue
    queue = Queue.new
    processed = 0

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber.schedule do
        3.times do |i|
          queue << i
          sleep 0.1
        end

        queue.close
      end

      Fiber.schedule do
        while item = queue.pop
          processed += 1
        end
      end

      scheduler.run
    end

    thread.join

    assert processed == 3
  end

  def test_mutex_deadlock
    err = /No live threads left. Deadlock\?/
    assert_in_out_err %W[-I#{__dir__} -], <<-RUBY, ['in synchronize'], err, success: false
    require 'scheduler'
    mutex = Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Thread.current.scheduler = scheduler

      Fiber.schedule do
        raise unless Thread.scheduler == scheduler

        mutex.synchronize do
          puts 'in synchronize'
          Fiber.yield
        end
      end

      mutex.lock
    end

    thread.join
    RUBY
  end
end
