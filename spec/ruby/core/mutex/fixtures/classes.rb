module MutexSpecs
  # A scheduler whose unblock can be called from any thread, recording the
  # unblocked fiber instead of resuming it.
  class UnblockScheduler
    attr_reader :unblocked

    def initialize
      @unblocked = Thread::Queue.new
    end

    def block(blocker, timeout = nil)
      Fiber.yield
    end

    def unblock(blocker, fiber)
      @unblocked << fiber
    end

    def kernel_sleep(duration = nil)
      Fiber.yield
    end

    def io_wait(io, events, timeout)
      Fiber.yield
    end

    def fiber(&block)
      Fiber.new(blocking: false, &block).tap(&:resume)
    end

    def fiber_interrupt(fiber, exception)
      # ignore it
    end
  end
end
