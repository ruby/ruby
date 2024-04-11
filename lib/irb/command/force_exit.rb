# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class ForceExit < Base
      category "IRB"
      description "Exit the current process."

      def execute(*)
        throw :IRB_EXIT, true
      rescue UncaughtThrowError
        Kernel.exit!
      end
    end
  end

  # :startdoc:
end
