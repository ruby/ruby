module FiberSpecs

  class NewFiberToRaise
    def self.raise(*args, **kwargs)
      fiber = Fiber.new { Fiber.yield }
      fiber.resume
      fiber.raise(*args, **kwargs)
    end
  end

  class CustomError < StandardError; end
end
