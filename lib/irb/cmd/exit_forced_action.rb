# frozen_string_literal: true

require_relative "nop"

module IRB
  # :stopdoc:

  module ExtendCommand
    class ExitForcedAction < Nop
      category "IRB"
      description "Exit the current process."

      def execute(*)
        IRB.irb_exit!
      rescue UncaughtThrowError
        Kernel.exit(0)
      end
    end
  end

  # :startdoc:
end
