# frozen_string_literal: false
#   multi.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require_relative "nop"

module IRB
  # :stopdoc:

  module ExtendCommand
    class MultiIRBCommand < Nop
      def initialize(conf)
        super
        extend_irb_context
      end

      private

      def extend_irb_context
        # this extension patches IRB context like IRB.CurrentContext
        require_relative "../ext/multi-irb"
      end
    end

    class IrbCommand < MultiIRBCommand
      def execute(*obj)
        IRB.irb(nil, *obj)
      end
    end

    class Jobs < MultiIRBCommand
      def execute
        IRB.JobManager
      end
    end

    class Foreground < MultiIRBCommand
      def execute(key)
        IRB.JobManager.switch(key)
      end
    end

    class Kill < MultiIRBCommand
      def execute(*keys)
        IRB.JobManager.kill(*keys)
      end
    end
  end

  # :startdoc:
end
