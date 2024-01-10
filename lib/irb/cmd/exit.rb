# frozen_string_literal: true

require_relative "nop"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Exit < Nop
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
