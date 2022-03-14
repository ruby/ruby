# frozen_string_literal: false
#
#   change-ws.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

require_relative "nop"
require_relative "../ext/change-ws"

module IRB
  # :stopdoc:

  module ExtendCommand

    class CurrentWorkingWorkspace < Nop
      def execute(*obj)
        irb_context.main
      end
    end

    class ChangeWorkspace < Nop
      def execute(*obj)
        irb_context.change_workspace(*obj)
        irb_context.main
      end
    end
  end

  # :startdoc:
end
