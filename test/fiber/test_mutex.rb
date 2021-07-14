# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberMutex < Test::Unit::TestCase
  def test_mutex_synchronize
    mutex = Thread::Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        assert_not_predicate Fiber, :blocking?

        mutex.synchronize do
          assert_not_predicate Fiber, :blocking?
        end
      end
    end

    thread.join
  end

  def test_mutex_interleaved_locking
    mutex = Thread::Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

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

  def test_mutex_thread
    mutex = Thread::Mutex.new
    mutex.lock

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        mutex.lock
        sleep 0.1
        mutex.unlock
      end

      scheduler.run
    end

    sleep 0.1
    mutex.unlock

    thread.join
  end

  def test_mutex_fiber_raise
    mutex = Thread::Mutex.new
    ran = false

    main = Thread.new do
      mutex.lock

      thread = Thread.new do
        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        f = Fiber.schedule do
          assert_raise_with_message(RuntimeError, "bye") do
            mutex.lock
          end

          ran = true
        end

        Fiber.schedule do
          f.raise "bye"
        end
      end

      thread.join
    end

    main.join # causes mutex to be released
    assert_equal false, mutex.locked?
    assert_equal true, ran
  end

  def test_condition_variable
    mutex = Thread::Mutex.new
    condition = Thread::ConditionVariable.new

    signalled = 0

    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

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
    end.join

    assert_equal 3, signalled
  end

  def test_queue
    queue = Thread::Queue.new
    processed = 0

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

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

    assert_equal 3, processed
  end

  def test_queue_pop_waits
    queue = Thread::Queue.new
    running = false

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        result = queue.pop
      end

      running = true
      scheduler.run
      result
    end

    Thread.pass until running
    sleep 0.1

    queue << :done
    assert_equal :done, thread.value
  end

  def test_mutex_deadlock
    error_pattern = /No live threads left. Deadlock\?/

    assert_in_out_err %W[-I#{__dir__} -], <<-RUBY, ['in synchronize'], error_pattern, success: false
    require 'scheduler'
    mutex = Thread::Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
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
