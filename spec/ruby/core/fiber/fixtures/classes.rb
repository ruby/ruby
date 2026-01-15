module FiberSpecs

  class NewFiberToRaise
    def self.raise(*args, **kwargs, &block)
      fiber = Fiber.new do
        if block_given?
          block.call do
            Fiber.yield
          end
        else
          Fiber.yield
        end
      end

      fiber.resume

      fiber.raise(*args, **kwargs)
    end
  end

  class CustomError < StandardError; end
end
