# frozen_string_literal: true

if RUBY_VERSION >= "2.5"
  module Kernel
    path = "#{__dir__}/"
    original_warn = instance_method(:warn)
    Module.new {define_method(:warn, original_warn)}
    original_warn = method(:warn)

    module_function define_method(:warn) {|*messages, uplevel: nil|
      if uplevel
        uplevel, = [uplevel].pack("l!").unpack("l!")
        if uplevel >= 0
          start = 0
          begin
            loc, = caller_locations(start, 1)
            break start += uplevel unless loc
            start += 1
          end while (loc.path.start_with?(path) or (uplevel -= 1) >= 0)
          uplevel = start
        end
        original_warn.call(*messages, uplevel: uplevel)
      else
        original_warn.call(*messages)
      end
    }
  end
end
