# frozen_string_literal: true

# Polyfill for Kernel#warn with the category parameter. Not all Ruby engines
# have Method#parameters implemented, so we check the arity instead if
# necessary.
if (method = Kernel.instance_method(:warn)).respond_to?(:parameters) ? method.parameters.none? { |_, name| name == :category } : (method.arity == -1)
  Kernel.prepend(
    Module.new {
      def warn(*msgs, uplevel: nil, category: nil) # :nodoc:
        uplevel =
          case uplevel
          when nil
            1
          when Integer
            uplevel + 1
          else
            uplevel.to_int + 1
          end

        super(*msgs, uplevel: uplevel)
      end
    }
  )

  Object.prepend(
    Module.new {
      def warn(*msgs, uplevel: nil, category: nil) # :nodoc:
        uplevel =
          case uplevel
          when nil
            1
          when Integer
            uplevel + 1
          else
            uplevel.to_int + 1
          end

        super(*msgs, uplevel: uplevel)
      end
    }
  )
end
