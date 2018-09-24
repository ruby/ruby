# frozen_string_literal: true

if RUBY_VERSION >= "2.5"
  module Kernel
    path = "#{__dir__}/"
    original_warn = instance_method(:warn)
    Module.new {define_method(:warn, original_warn)}
    original_warn = method(:warn)

    module_function define_method(:warn) {|message, uplevel: nil|
      if uplevel
        while (loc, = caller_locations(uplevel, 1); loc && loc.path.start_with?(path))
          uplevel += 1
        end
        original_warn.call(message, uplevel: uplevel + 1)
      else
        original_warn.call(message)
      end
    }
  end
end
