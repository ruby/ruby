# frozen_string_literal: true

require_relative "nop"

module IRB
  # :stopdoc:

  module ExtendCommand
    class ForceExit < Nop
      category "IRB"
      description "Exit the current process."

      def execute(*)
        throw :IRB_EXIT, true
      rescue UncaughtThrowError
        Kernel.exit(0)
      end
    end
  end

  # :startdoc:
end
