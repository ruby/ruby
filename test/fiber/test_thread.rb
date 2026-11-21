# frozen_string_literal: true
require "test/unit"
require_relative 'scheduler'

class TestFiberThread < Test::Unit::TestCase
  include ParkedWaiterAssertions

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

  def test_thread_join_abandoned_by_terminated_thread
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        queue = Thread::Queue.new
        target = Thread.new { queue.pop }

        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          # The fiber blocks in Thread#join and is never resumed, so this
          # thread's exit must take its waiter off target's join list.
          Fiber.schedule { target.join }
        end.join

        GC.start
        queue << i
        assert_equal i, target.value
      end
    RUBY
  end

  def test_thread_join_abandoned_fiber_garbage_collected
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        queue = Thread::Queue.new
        target = Thread.new { queue.pop }

        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          # Only this thread keeps the fiber blocked in Thread#join alive; it
          # must not be collected while its waiter is on target's join list.
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

  def test_mutex_lock_abandoned_by_terminated_thread
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        mutex = Thread::Mutex.new
        mutex.lock

        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          Fiber.schedule { mutex.lock }
        end.join

        GC.start
        10.times { Fiber.new { Array.new(100, i) }.resume }
        mutex.unlock
        assert_predicate mutex, :try_lock
        mutex.unlock
      end
    RUBY
  end

  def test_condition_variable_wait_abandoned_by_terminated_thread
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        mutex = Thread::Mutex.new
        cv = Thread::ConditionVariable.new

        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          Fiber.schedule { mutex.synchronize { cv.wait(mutex) } }
        end.join

        GC.start
        10.times { Fiber.new { Array.new(100, i) }.resume }
        cv.broadcast
      end
    RUBY
  end

  def test_queue_pop_abandoned_by_terminated_thread
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        queue = Thread::Queue.new

        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          Fiber.schedule { queue.pop }
        end.join

        assert_equal 0, queue.num_waiting

        GC.start
        10.times { Fiber.new { Array.new(100, i) }.resume }
        queue << i
        assert_equal i, queue.pop
      end
    RUBY
  end

  def test_sized_queue_push_abandoned_by_terminated_thread
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        queue = Thread::SizedQueue.new(1)
        queue << i

        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          Fiber.schedule { queue << :abandoned }
        end.join

        assert_equal 0, queue.num_waiting

        GC.start
        10.times { Fiber.new { Array.new(100, i) }.resume }
        assert_equal i, queue.pop
        assert_equal 0, queue.size
      end
    RUBY
  end

  def test_queue_pop_abandoned_fiber_garbage_collected
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY', timeout: 60)
      100.times do |i|
        queue = Thread::Queue.new

        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          Fiber.schedule { queue.pop }
          Fiber.set_scheduler(nil)

          GC.start
          10.times { Fiber.new { Array.new(100, i) }.resume }

          queue << i
        end.join
      end
    RUBY
  end

  # A fiber parked in Thread#join by a scheduler that never resumes it leaves its
  # on-stack join waiter linked into the target's join list. Once the fiber was
  # collected, the target's exit read the freed waiter.
  def test_thread_join_from_collected_fiber
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY')
      100.times do |i|
        target = nil
        Thread.new do
          Fiber.set_scheduler(ParkingScheduler.new)
          Fiber.schedule { (target = Thread.new { sleep 0.001 }).join }
        end.join
        GC.start(full_mark: i.even?)
        target.join
      end
    RUBY
  end

  # The holder is a target thread that waits on a queue, so it is still
  # running when the joining fiber is collected; wake lets it exit.
  JOIN_TARGET = "Thread::Queue.new.then { |q| [Thread.new { q.pop }, q] }"
  JOIN = "->((t, _)) { t.join }"
  JOIN_WAKE = "->((t, q)) { q.push(nil); t.join }"

  def test_thread_join_from_collected_fiber_old_target
    assert_parked_waiter_released(JOIN_TARGET, JOIN, JOIN_WAKE, old_holder: true)
  end

  # The joining fiber outlives its thread, so the target's exit wakes a waiter
  # of a dead thread.
  def test_thread_join_from_fiber_of_dead_thread
    assert_parked_waiter_released(JOIN_TARGET, JOIN, JOIN_WAKE, keep_fiber: true)
  end

  def test_thread_join_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released(JOIN_TARGET, JOIN, JOIN_WAKE, incremental: true)
  end
end
