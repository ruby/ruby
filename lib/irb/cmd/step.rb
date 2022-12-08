# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Step < DebugCommand
      def execute(*args)
        # Run `next` first to move out of binding.irb
        super(pre_cmds: "next", do_cmds: ["step", *args].join(" "))
      end
    end
  end

  # :startdoc:
end
