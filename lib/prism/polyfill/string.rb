# frozen_string_literal: true

# Polyfill for String#unpack1 with the offset parameter.
if String.instance_method(:unpack1).parameters.none? { |_, name| name == :offset }
  String.prepend(
    Module.new {
      def unpack1(format, offset: 0) # :nodoc:
        offset == 0 ? super(format) : self[offset..].unpack1(format) # steep:ignore
      end
    }
  )
end
