# frozen_string_literal: true

# FairScheduler — a CFS-style fiber scheduler that uses Fiber#runtime to order
# the ready queue.  Fibers that yielded cooperatively (small runtime) sort ahead
# of fibers that exhausted their full quantum (runtime ≈ quantum), giving
# IO-bound work natural priority over CPU-bound work without any explicit
# priority annotation.
#
# Usage:
#   require_relative "fair_scheduler"
#   Fiber.set_scheduler(FairScheduler.new)
#   Fiber.schedule { ... }
#
# See also: test/fiber/scheduler.rb (the base class)

require_relative "scheduler"

# Min-heap of fibers sorted ascending by Fiber#runtime.
# Lower runtime = yielded earlier in its quantum = scheduled first.
class RuntimeHeap
  def initialize
    @data = []
  end

  def push(fiber)
    @data << fiber
    sift_up(@data.size - 1)
  end

  def pop
    return nil if @data.empty?
    swap(0, @data.size - 1)
    fiber = @data.pop
    sift_down(0) unless @data.empty?
    fiber
  end

  def any?  = !@data.empty?
  def empty? = @data.empty?
  def size   = @data.size

  private

  def rt(i)
    f = @data[i]
    f.respond_to?(:runtime) ? f.runtime : 0
  end

  def swap(a, b)
    @data[a], @data[b] = @data[b], @data[a]
  end

  def sift_up(i)
    while i > 0
      p = (i - 1) / 2
      break if rt(p) <= rt(i)
      swap(p, i)
      i = p
    end
  end

  def sift_down(i)
    n = @data.size
    loop do
      l, r, s = 2*i+1, 2*i+2, i
      s = l if l < n && rt(l) < rt(s)
      s = r if r < n && rt(r) < rt(s)
      break if s == i
      swap(i, s)
      i = s
    end
  end
end

# Scheduler subclass that replaces the plain FIFO @ready array with a
# RuntimeHeap so fibers are dispatched in CFS order.
class FairScheduler < Scheduler
  # Called by rb_fiber_scheduler_yield when a fiber exhausts its quantum.
  # Pushes the fiber into the heap (sorted by its runtime at yield time)
  # and returns control to the scheduler's event loop.
  def yield
    ready_push(Fiber.current)
    @fiber.transfer
  end

  # Forward quantum: from Fiber.schedule to Fiber.new so callers can set
  # the scheduling quantum per-fiber without a separate assignment.
  def fiber(quantum: nil, **opts, &block)
    f = Fiber.new(blocking: false, **opts, **(quantum ? {quantum: quantum} : {}), &block)
    f.transfer
    f
  end

  # The run loop must also spin while the heap has ready fibers, since
  # CPU-bound fibers never touch @readable/@writable/@waiting/@blocking.
  def should_run_more?
    ready_any?
  end

  # Return 0 when the heap has work to do so IO.select returns immediately
  # instead of blocking forever waiting for IO events.
  def next_timeout
    return 0 if ready_any?
    super
  end

  protected

  def ready_push(fiber)
    @lock.synchronize { @heap.push(fiber) }
  end

  def ready_drain
    @lock.synchronize do
      fibers = []
      fibers << @heap.pop until @heap.empty?
      fibers
    end
  end

  def ready_any?
    @lock.synchronize { @heap.any? }
  end

  private

  def initialize(*)
    super
    @heap = RuntimeHeap.new
  end
end
