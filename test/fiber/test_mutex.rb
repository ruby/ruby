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

  # Regression test: a fiber parked in Fiber::Scheduler#block while waiting on a
  # locked mutex links an on-stack waiter into the mutex's wait queue. That wait
  # queue is not a GC root, and a scheduler is not required to retain the blocked
  # fiber, so nothing else necessarily keeps it reachable -- the VM must root the
  # parked fiber on its thread. Otherwise GC frees the fiber while it is parked,
  # and unlocking the mutex walks a dangling waiter node and crashes.
  def test_mutex_blocking_fiber_gc
    assert_separately([], <<~'RUBY')
      # A deliberately minimal scheduler: #block does not retain the blocked
      # fiber and #fiber discards the fiber it resumes, so the only thing that
      # can keep the parked fiber alive is the VM rooting it on its thread.
      class MinScheduler
        def block(blocker, timeout = nil)
          Fiber.yield
        end
        def unblock(blocker, fiber)
        end
        def fiber(&block)
          Fiber.new(blocking: false, &block).resume
          nil
        end
        def fiber_interrupt(fiber, exception); end
        def close; end
        def kernel_sleep(*); end
        def io_wait(*); end
        def process_wait(*); end
        def timeout_after(*); yield; end
        def blocking_operation_wait(work); work.call; end
      end

      mutex = Thread::Mutex.new
      mutex.lock

      Fiber.set_scheduler(MinScheduler.new)
      # Parks a fiber inside #block, linked into mutex's wait queue, then discards
      # every Ruby-level reference to it.
      Fiber.schedule do
        mutex.lock
        mutex.unlock
      end

      # If the parked fiber were not rooted by the VM, GC would free it here and
      # leave a dangling waiter in the mutex's wait queue.
      5.times { GC.start }

      # Walks the wait queue -- must not touch a freed fiber/waiter.
      mutex.unlock
      assert_equal(false, mutex.locked?)
    RUBY
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
      assert_includes error.message, "deadlock; lock already owned by another fiber belonging to the same thread"
    end
  ensure
    thr&.kill&.join
  end
end
