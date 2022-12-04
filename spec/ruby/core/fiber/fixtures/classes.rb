module FiberSpecs

  class NewFiberToRaise
    def self.raise(*args)
      fiber = Fiber.new { Fiber.yield }
      fiber.resume
      fiber.raise(*args)
    end
  end

  class CustomError < StandardError; end
end
