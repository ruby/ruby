# frozen_string_literal: true

# `uplevel` keyword argument of Kernel#warn is available since ruby 2.5.
if RUBY_VERSION >= "2.5"

  module Kernel
    path = "#{__dir__}/" # Frames to be skipped start with this path.

    # Suppress "method redefined" warning
    original_warn = instance_method(:warn)
    Module.new {define_method(:warn, original_warn)}

    original_warn = method(:warn)

    module_function define_method(:warn) {|*messages, uplevel: nil|
      unless uplevel
        return original_warn.call(*messages)
      end

      # Ensure `uplevel` fits a `long`
      uplevel, = [uplevel].pack("l!").unpack("l!")

      if uplevel >= 0
        start = 0
        while uplevel >= 0
          loc, = caller_locations(start, 1)
          unless loc
            # No more backtrace
            start += uplevel
            break
          end

          start += 1

          unless loc.path.start_with?(path)
            # Non-rubygems frames
            uplevel -= 1
          end
        end
        uplevel = start
      end
      original_warn.call(*messages, uplevel: uplevel)
    }
  end
end
