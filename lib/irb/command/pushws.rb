# frozen_string_literal: true
#
#   change-ws.rb -
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative "../ext/workspaces"

module IRB
  # :stopdoc:

  module Command
    class Workspaces < Base
      category "Workspace"
      description "Show workspaces."

      def execute(*obj)
        inspection_resuls = irb_context.instance_variable_get(:@workspace_stack).map do |ws|
          truncated_inspect(ws.main)
        end

        puts "[" + inspection_resuls.join(", ") + "]"
      end

      private

      def truncated_inspect(obj)
        obj_inspection = obj.inspect

        if obj_inspection.size > 20
          obj_inspection = obj_inspection[0, 19] + "...>"
        end

        obj_inspection
      end
    end

    class PushWorkspace < Workspaces
      category "Workspace"
      description "Push an object to the workspace stack."

      def execute(*obj)
        irb_context.push_workspace(*obj)
        super
      end
    end

    class PopWorkspace < Workspaces
      category "Workspace"
      description "Pop a workspace from the workspace stack."

      def execute(*obj)
        irb_context.pop_workspace(*obj)
        super
      end
    end
  end

  # :startdoc:
end
