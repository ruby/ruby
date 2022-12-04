# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module ExtendCommand
    class Finish < Debug
      def execute(*args)
        super(do_cmds: ["finish", *args].join(" "))
      end
    end
  end

  # :startdoc:
end
