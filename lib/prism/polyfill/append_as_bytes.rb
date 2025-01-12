# frozen_string_literal: true

# Polyfill for String#append_as_bytes, which didn't exist until Ruby 3.4.
if !("".respond_to?(:append_as_bytes))
  String.include(
    Module.new {
      def append_as_bytes(*args)
        args.each { self.<<(_1.b) } # steep:ignore
      end
    }
  )
end
