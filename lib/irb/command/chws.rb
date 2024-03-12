# frozen_string_literal: true
#
#   change-ws.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
require_relative "../ext/change-ws"

module IRB
  # :stopdoc:

  module Command

    class CurrentWorkingWorkspace < Base
      category "Workspace"
      description "Show the current workspace."

      def execute(*obj)
        irb_context.main
      end
    end

    class ChangeWorkspace < Base
      category "Workspace"
      description "Change the current workspace to an object."

      def execute(*obj)
        irb_context.change_workspace(*obj)
        irb_context.main
      end
    end
  end

  # :startdoc:
end
