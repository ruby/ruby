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
  QUEUE_PUSH_POP = "->(q) { q.push(1); assert_equal 1, q.pop }"
  FULL_SIZED_QUEUE = "Thread::SizedQueue.new(1).tap { _1.push(0) }"
  SIZED_QUEUE_DRAIN = "->(q) { assert_equal 0, q.pop; assert_empty q }"

  # A scheduler fiber parked forever in a queue operation was collected while
  # its on-stack waiter stayed in the queue's wait list; waking it read it.
  def test_pop_from_collected_fiber
    assert_parked_waiter_released("Thread::Queue.new", QUEUE_POP, QUEUE_PUSH_POP)
  end

  # The queue is old and the fiber dies in a minor GC.
  def test_pop_from_collected_fiber_old_queue
    assert_parked_waiter_released("Thread::Queue.new", QUEUE_POP, QUEUE_PUSH_POP, old_holder: true)
  end

  def test_pop_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released("Thread::Queue.new", QUEUE_POP, QUEUE_PUSH_POP, incremental: true)
  end

  def test_sized_queue_pop_from_collected_fiber
    assert_parked_waiter_released("Thread::SizedQueue.new(1)", QUEUE_POP, QUEUE_PUSH_POP)
  end

  def test_sized_queue_pop_from_collected_fiber_old_queue
    assert_parked_waiter_released("Thread::SizedQueue.new(1)", QUEUE_POP, QUEUE_PUSH_POP, old_holder: true)
  end

  def test_sized_queue_push_from_collected_fiber
    assert_parked_waiter_released(FULL_SIZED_QUEUE, QUEUE_PUSH, SIZED_QUEUE_DRAIN)
  end

  def test_sized_queue_push_from_collected_fiber_old_queue
    assert_parked_waiter_released(FULL_SIZED_QUEUE, QUEUE_PUSH, SIZED_QUEUE_DRAIN, old_holder: true)
  end

  def test_sized_queue_push_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released(FULL_SIZED_QUEUE, QUEUE_PUSH, SIZED_QUEUE_DRAIN, incremental: true)
  end

  # Releasing an abandoned waiter when its thread exits keeps the waiting
  # counts in step.
  def test_num_waiting_after_collected_fiber
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY')
      queue = Thread::Queue.new
      sized = Thread::SizedQueue.new(1)
      sized.push(0)
      Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        Fiber.schedule { queue.pop }
        Fiber.schedule { sized.push(1) }
      end.join
      assert_equal 0, queue.num_waiting
      assert_equal 0, sized.num_waiting
      GC.start
      assert_equal 0, queue.num_waiting
      assert_equal 0, sized.num_waiting
    RUBY
  end

  # A fiber kept alive past its thread's death can never be resumed, so its
  # waiter stops counting once that thread has exited.
  def test_num_waiting_after_fiber_outlives_thread
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY')
      $parked = []
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
      assert_equal 0, by_wakeup.num_waiting
      by_wakeup.push(1)
      assert_equal 0, by_wakeup.num_waiting
      sized.pop
      assert_equal 0, sized.num_waiting
      GC.start
      assert_equal 0, by_gc.num_waiting
      assert_equal 3, $parked.size
    RUBY
  end

  # The child resets the queue on first use. The forking thread's exit then
  # released the parent's waiter against the reset queue, so num_waiting went
  # to -1 and its stale list pointers were written into the new waitq.
  def test_num_waiting_after_fork_with_parked_fiber
    omit "fork not supported" unless Process.respond_to?(:fork)
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY')
      queue = Thread::Queue.new
      r, w = IO.pipe
      parent = Process.pid
      at_exit { w.puts queue.num_waiting unless Process.pid == parent }

      pid = nil
      Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        Fiber.schedule { queue.pop }
        # Fork from the thread's root fiber, so the child's thread exits
        # through the normal thread termination path.
        w.puts queue.num_waiting unless (pid = fork)
      end.join
      w.close
      Process.wait(pid)
      assert_predicate $?, :success?
      assert_equal %w[0 0], r.read.split
    RUBY
  end

  # A fiber parked in a queue at fork belongs to the child's thread and may be
  # resumed there; its wait was already released, so it must not be released again.
  def test_parked_fiber_resumed_after_fork
    omit "fork not supported" unless Process.respond_to?(:fork)
    assert_separately([], PARKING_SCHEDULER + <<~'RUBY')
      queue = Thread::Queue.new
      sized = Thread::SizedQueue.new(1)
      sized.push(0)
      r, w = IO.pipe

      pid = nil
      Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        popped = nil
        popper = Fiber.schedule { popped = queue.pop }
        pusher = Fiber.schedule { sized.push(1) }
        unless (pid = fork)
          queue.push(:x)
          popper.transfer
          sized.pop
          pusher.transfer
          w.puts [popped, queue.num_waiting, sized.num_waiting, sized.pop].inspect
          w.close
          exit!(0)
        end
      end.join
      w.close
      Process.wait(pid)
      assert_predicate $?, :success?
      assert_equal "[:x, 0, 0, 1]", r.read.chomp
    RUBY
  end
end
