# frozen_string_literal: true

# Polyfill for Kernel#warn with the category parameter. Not all Ruby engines
# have Method#parameters implemented, so we check the arity instead if
# necessary.
if (method = Kernel.instance_method(:warn)).respond_to?(:parameters) ? method.parameters.none? { |_, name| name == :category } : (method.arity == -1)
  Kernel.prepend(
    Module.new {
      def warn(*msgs, uplevel: nil, category: nil) # :nodoc:
        case uplevel
        when nil
          super(*msgs)
        when Integer
          super(*msgs, uplevel: uplevel + 1)
        else
          super(*msgs, uplevel: uplevel.to_int + 1)
        end
      end
    }
  )

  Object.prepend(
    Module.new {
      def warn(*msgs, uplevel: nil, category: nil) # :nodoc:
        case uplevel
        when nil
          super(*msgs)
        when Integer
          super(*msgs, uplevel: uplevel + 1)
        else
          super(*msgs, uplevel: uplevel.to_int + 1)
        end
      end
    }
  )
end
