# frozen_string_literal: true

require_relative "debug"

module IRB
  # :stopdoc:

  module Command
    class Catch < DebugCommand
      def self.transform_args(args)
        args&.dump
      end

      def execute(*args)
        super(pre_cmds: ["catch", *args].join(" "))
      end
    end
  end

  # :startdoc:
end
