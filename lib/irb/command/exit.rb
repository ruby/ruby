# frozen_string_literal: true

module IRB
  # :stopdoc:

  module Command
    class Exit < Base
      category "IRB"
      description "Exit the current irb session."

      def execute(*)
        IRB.irb_exit
      rescue UncaughtThrowError
        Kernel.exit
      end
    end
  end

  # :startdoc:
end
