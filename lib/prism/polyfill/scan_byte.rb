# frozen_string_literal: true

require "strscan"

# Polyfill for StringScanner#scan_byte, which didn't exist until Ruby 3.4.
if !(StringScanner.instance_methods.include?(:scan_byte))
  StringScanner.include(
    Module.new {
      def scan_byte # :nodoc:
        get_byte&.b&.ord
      end
    }
  )
end
