# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module Command
    class Info < DebugCommand
      def execute(arg)
        execute_debug_command(pre_cmds: "info #{arg}".rstrip)
      end
    end
  end

  # :startdoc:
end
