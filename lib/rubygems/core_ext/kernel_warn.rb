# frozen_string_literal: true

# `uplevel` keyword argument of Kernel#warn is available since ruby 2.5.
if RUBY_VERSION >= "2.5"

  module Kernel
    rubygems_path = "#{__dir__}/" # Frames to be skipped start with this path.

    original_warn = method(:warn)

    remove_method :warn

    class << self
      remove_method :warn
    end

    module_function define_method(:warn) {|*messages, **kw|
      unless uplevel = kw[:uplevel]
        if Gem.java_platform?
          return original_warn.call(*messages)
        else
          return original_warn.call(*messages, **kw)
        end
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

          path = loc.path
          unless path.start_with?(rubygems_path) or path.start_with?('<internal:')
            # Non-rubygems frames
            uplevel -= 1
          end
        end
        uplevel = start
      end

      kw[:uplevel] = uplevel
      original_warn.call(*messages, **kw)
    }
  end
end
