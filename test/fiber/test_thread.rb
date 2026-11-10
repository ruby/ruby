# frozen_string_literal: true
require "test/unit"
require_relative 'scheduler'

class TestFiberThread < Test::Unit::TestCase
  def test_thread_join
    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        result = Thread.new{:done}.value
      end

      scheduler.run
      result
    end

    assert_equal :done, thread.value
  end

  def test_thread_join_timeout
    sleeper = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        sleeper = Thread.new{sleep}
        sleeper.join(0.1)
      end

      scheduler.run
    end

    thread.join

    assert_predicate sleeper, :alive?
  ensure
    sleeper&.kill&.join
  end

  def test_thread_join_implicit
    sleeping = false
    finished = false

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        sleeping = true
        sleep(0.1)
        finished = true
      end

      :done
    end

    Thread.pass until sleeping

    thread.join

    assert_equal :done, thread.value
    assert finished, "Scheduler thread's task should be finished!"
  end

  def test_thread_join_blocking
    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      result = nil
      Fiber.schedule do
        Fiber.new(blocking: true) do
          # This can deadlock if the blocking state is not taken into account:
          Thread.new do
            sleep(0)
            result = :done
          end.join
        end.resume
      end

      scheduler.run
      result
    end

    assert_equal :done, thread.value
  end

  def test_spurious_unblock_during_thread_join
    ready = Thread::Queue.new

    target_thread = Thread.new do
      ready.pop
      :success
    end

    Thread.pass until target_thread.status == "sleep"

    result = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      # Create a fiber that will join a long-running thread:
      joining_fiber = Fiber.schedule do
        result = target_thread.value
      end

      # Create another fiber that spuriously unblocks the joining fiber:
      Fiber.schedule do
        # This interrupts the join in joining_fiber:
        scheduler.unblock(:spurious_wakeup, joining_fiber)

        # This allows the unblock to be processed:
        sleep(0)

        # This allows the target thread to finish:
        ready.push(:done)
      end

      scheduler.run
    end

    thread.join

    assert_equal :success, result
  end

  def test_broken_unblock
    thread = Thread.new do
      Thread.current.report_on_exception = false

      scheduler = BrokenUnblockScheduler.new

      Fiber.set_scheduler scheduler

      Fiber.schedule do
        Thread.new{
          Thread.current.report_on_exception = false
        }.join
      end

      scheduler.run
    ensure
      scheduler.close
    end

    assert_raise(RuntimeError) do
      thread.join
    end
  end

  def test_thread_join_hang
    inner = nil
    thread = Thread.new do
      scheduler = SleepingUnblockScheduler.new

      Fiber.set_scheduler scheduler

      Fiber.schedule do
        inner = Thread.new{sleep(0.01)}
        inner.value
      end
    end

    thread.join
  ensure
    inner&.join
  end

  ABANDONING_SCHEDULER = <<~'RUBY'
    # A scheduler which never resumes the fibers blocked in #block.
    class AbandoningScheduler
      def initialize = @main = Fiber.current
      def block(blocker, timeout = nil) = @main.transfer
      def unblock(blocker, fiber) = nil
      def kernel_sleep(duration = nil) = block(:sleep, duration)
      def io_wait(io, events, timeout) = block(:io_wait, timeout)
      def fiber_interrupt(fiber, exception) = nil
      def close = nil

      def fiber(&block)
        fiber = Fiber.new(blocking: false, &block)
        fiber.transfer
        fiber
      end
    end
  RUBY

  def test_thread_join_abandoned_by_terminated_thread
    assert_separately([], ABANDONING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        queue = Thread::Queue.new
        target = Thread.new { queue.pop }

        Thread.new do
          Fiber.set_scheduler(AbandoningScheduler.new)
          # The fiber blocks in Thread#join and is never resumed, so its waiter
          # stays on target's join list after this thread terminates.
          Fiber.schedule { target.join }
        end.join

        GC.start
        queue << i
        assert_equal i, target.value
      end
    RUBY
  end

  def test_thread_join_abandoned_fiber_garbage_collected
    assert_separately([], ABANDONING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        queue = Thread::Queue.new
        target = Thread.new { queue.pop }

        Thread.new do
          Fiber.set_scheduler(AbandoningScheduler.new)
          # Nothing references the fiber blocked in Thread#join while this
          # thread is still alive.
          Fiber.schedule { target.join }
          Fiber.set_scheduler(nil)

          GC.start
          10.times { Fiber.new { Array.new(100, i) }.resume }

          queue << i
          assert_equal i, target.value
        end.join
      end
    RUBY
  end
end
