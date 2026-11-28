# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberQueue < Test::Unit::TestCase
  include ParkedWaiterAssertions

  def test_pop_with_timeout
    queue = Thread::Queue.new
    kill = false
    result = :unspecified

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler(scheduler)

      Fiber.schedule do
        result = queue.pop(timeout: 0.0001)
      end

      scheduler.run
    end
    until thread.join(2)
      kill = true
      thread.kill
    end

    assert_false(kill, 'Getting stuck due to a possible compiler bug.')
    assert_nil result
  end

  def test_pop_with_timeout_and_value
    queue = Thread::Queue.new
    queue.push(:something)
    kill = false
    result = :unspecified

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler(scheduler)

      Fiber.schedule do
        result = queue.pop(timeout: 0.0001)
      end

      scheduler.run
    end
    until thread.join(2)
      kill = true
      thread.kill
    end

    assert_false(kill, 'Getting stuck due to a possible compiler bug.')
    assert_equal :something, result
  end

  QUEUE_POP = "->(q) { q.pop }"
  QUEUE_PUSH = "->(q) { q.push(1) }"
  FULL_SIZED_QUEUE = "Thread::SizedQueue.new(1).tap { _1.push(0) }"

  # A scheduler fiber parked forever in a queue operation was collected while
  # its on-stack waiter stayed in the queue's wait list; waking it read it.
  def test_pop_from_collected_fiber
    assert_parked_waiter_released("Thread::Queue.new", QUEUE_POP, QUEUE_PUSH)
  end

  # The queue is old and the fiber dies in a minor GC, so the queue must be
  # remembered for its waiter to be dropped.
  def test_pop_from_collected_fiber_old_queue
    assert_parked_waiter_released("Thread::Queue.new", QUEUE_POP, QUEUE_PUSH, old_holder: true)
  end

  def test_pop_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released("Thread::Queue.new", QUEUE_POP, QUEUE_PUSH, incremental: true)
  end

  def test_sized_queue_pop_from_collected_fiber
    assert_parked_waiter_released("Thread::SizedQueue.new(1)", QUEUE_POP, QUEUE_PUSH)
  end

  def test_sized_queue_pop_from_collected_fiber_old_queue
    assert_parked_waiter_released("Thread::SizedQueue.new(1)", QUEUE_POP, QUEUE_PUSH, old_holder: true)
  end

  def test_sized_queue_push_from_collected_fiber
    assert_parked_waiter_released(FULL_SIZED_QUEUE, QUEUE_PUSH, QUEUE_POP)
  end

  def test_sized_queue_push_from_collected_fiber_old_queue
    assert_parked_waiter_released(FULL_SIZED_QUEUE, QUEUE_PUSH, QUEUE_POP, old_holder: true)
  end

  def test_sized_queue_push_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released(FULL_SIZED_QUEUE, QUEUE_PUSH, QUEUE_POP, incremental: true)
  end

  # Dropping a collected waiter keeps the waiting counts in step.
  def test_num_waiting_after_collected_fiber
    assert_separately([], <<~'RUBY')
      class ParkingScheduler
        def initialize = @main = Fiber.current
        def block(blocker, timeout = nil) = @main.transfer
        def unblock(blocker, fiber) = nil
        def kernel_sleep(duration = nil) = block(:sleep, duration)
        def io_wait(io, events, timeout) = block(:io_wait, timeout)
        def fiber_interrupt(fiber, exception) = nil
        def close = nil
        def fiber(&) = Fiber.new(blocking: false, &).tap(&:transfer)
      end

      queue = Thread::Queue.new
      sized = Thread::SizedQueue.new(1)
      sized.push(0)
      Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        Fiber.schedule { queue.pop }
        Fiber.schedule { sized.push(1) }
      end.join
      assert_equal 1, queue.num_waiting
      assert_equal 1, sized.num_waiting
      GC.start
      assert_equal 0, queue.num_waiting
      assert_equal 0, sized.num_waiting
    RUBY
  end

  # A fiber kept alive past its thread's death can never be resumed, so its
  # waiter stops counting, whether a wakeup or a GC drops it first.
  def test_num_waiting_after_fiber_outlives_thread
    assert_separately([], <<~'RUBY')
      $parked = []
      class ParkingScheduler
        def initialize = @main = Fiber.current
        def block(blocker, timeout = nil)
          $parked << Fiber.current
          @main.transfer
        end
        def unblock(blocker, fiber) = nil
        def kernel_sleep(duration = nil) = block(:sleep, duration)
        def io_wait(io, events, timeout) = block(:io_wait, timeout)
        def fiber_interrupt(fiber, exception) = nil
        def close = nil
        def fiber(&) = Fiber.new(blocking: false, &).tap(&:transfer)
      end

      by_wakeup = Thread::Queue.new
      by_gc = Thread::Queue.new
      sized = Thread::SizedQueue.new(1)
      sized.push(0)
      Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        Fiber.schedule { by_wakeup.pop }
        Fiber.schedule { by_gc.pop }
        Fiber.schedule { sized.push(1) }
      end.join
      assert_equal 1, by_wakeup.num_waiting
      by_wakeup.push(1)
      assert_equal 0, by_wakeup.num_waiting
      sized.pop
      assert_equal 0, sized.num_waiting
      GC.start
      assert_equal 0, by_gc.num_waiting
      assert_equal 3, $parked.size
    RUBY
  end
end
