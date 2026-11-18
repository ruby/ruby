# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberMutex < Test::Unit::TestCase
  include ParkedWaiterAssertions

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
    pending = 0

    Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        mutex.synchronize do
          3.times do
            condition.wait(mutex) while pending.zero?
            pending -= 1
            signalled += 1
          end
        end
      end

      Fiber.schedule do
        3.times do
          mutex.synchronize do
            pending += 1
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
    error_pattern = /lock already owned by another fiber/

    assert_in_out_err %W[-I#{__dir__} -], <<-RUBY, ['in synchronize'], error_pattern, success: false
    require 'scheduler'
    mutex = Thread::Mutex.new

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        mutex.synchronize do
          puts 'in synchronize'
          scheduler.transfer
        end
      end

      mutex.lock
    end

    thread.join
    RUBY
  end

  def test_mutex_fiber_deadlock_no_scheduler
    thr = Thread.new do
      loop do
        sleep 1
      end
    end

    mutex = Mutex.new
    mutex.synchronize do
      error = assert_raise ThreadError do
        Fiber.new do
          mutex.lock
        end.resume
      end
      assert_include error.message, "deadlock; lock already owned by another fiber belonging to the same thread"
    end
  ensure
    thr&.kill&.join
  end

  MUTEX_LOCKED = "Mutex.new.tap(&:lock)"
  MUTEX_LOCK = "->(m) { m.lock }"
  MUTEX_UNLOCK = "->(m) { m.unlock }"

  # A scheduler fiber parked forever in Mutex#lock was collected while its
  # on-stack waiter stayed in the mutex's waitq; unlock then read it.
  def test_mutex_lock_from_collected_fiber
    assert_parked_waiter_released(MUTEX_LOCKED, MUTEX_LOCK, MUTEX_UNLOCK)
  end

  # Same, but the mutex is old and the fiber dies in a minor GC, so the mutex
  # must be remembered for its waiter to be dropped.
  def test_mutex_lock_from_collected_fiber_old_mutex
    assert_parked_waiter_released(MUTEX_LOCKED, MUTEX_LOCK, MUTEX_UNLOCK, old_holder: true)
  end

  # The parked fiber outlives its thread; unlock used to rb_bug on the
  # waiter's THREAD_KILLED status.
  def test_mutex_lock_from_fiber_of_dead_thread
    assert_parked_waiter_released(MUTEX_LOCKED, MUTEX_LOCK, MUTEX_UNLOCK, keep_fiber: true)
  end

  # The mutex is marked by an incremental GC before its first scheduler wait
  # flags it, so declaring the flag must queue it for that cycle's weak pass.
  def test_mutex_lock_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released(MUTEX_LOCKED, MUTEX_LOCK, MUTEX_UNLOCK, incremental: true)
  end

  CONDVAR = "Thread::ConditionVariable.new"
  CONDVAR_WAIT = "->(cv) { m = Mutex.new; m.synchronize { cv.wait(m) } }"
  CONDVAR_SIGNAL = "->(cv) { cv.signal }"

  def test_condition_variable_wait_from_collected_fiber
    assert_parked_waiter_released(CONDVAR, CONDVAR_WAIT, CONDVAR_SIGNAL)
  end

  def test_condition_variable_wait_from_collected_fiber_old_condvar
    assert_parked_waiter_released(CONDVAR, CONDVAR_WAIT, CONDVAR_SIGNAL, old_holder: true)
  end

  def test_condition_variable_wait_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released(CONDVAR, CONDVAR_WAIT, CONDVAR_SIGNAL, incremental: true)
  end
end
