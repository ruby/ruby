# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module Command
    class Delete < DebugCommand
      def execute(*args)
        super(pre_cmds: ["delete", *args].join(" "))
      end
    end
  end

  # :startdoc:
end
