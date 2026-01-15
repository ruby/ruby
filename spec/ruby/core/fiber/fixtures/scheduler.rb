module FiberSpecs

  class LoggingScheduler
    attr_reader :events
    def initialize
      @events = []
    end

    def block(*args)
      @events << { event: :block, fiber: Fiber.current, args: args }
      Fiber.yield
    end

    def io_wait(*args)
      @events << { event: :io_wait, fiber: Fiber.current, args: args }
      Fiber.yield
    end

    def kernel_sleep(*args)
      @events << { event: :kernel_sleep, fiber: Fiber.current, args: args }
      Fiber.yield
    end

    def unblock(*args)
      @events << { event: :unblock, fiber: Fiber.current, args: args }
      Fiber.yield
    end

    def fiber_interrupt(*args)
      @events << { event: :fiber_interrupt, fiber: Fiber.current, args: args }
      Fiber.yield
    end
  end

end
