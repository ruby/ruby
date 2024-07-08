# frozen_string_literal: true

module IRB
  module Command
    class CD < Base
      category "Workspace"
      description "Move into the given object or leave the current context."

      help_message(<<~HELP)
        Usage: cd ([target]|..)

        IRB uses a stack of workspaces to keep track of context(s), with `pushws` and `popws` commands to manipulate the stack.
        The `cd` command is an attempt to simplify the operation and will be subject to change.

        When given:
        - an object, cd will use that object as the new context by pushing it onto the workspace stack.
        - "..", cd will leave the current context by popping the top workspace off the stack.
        - no arguments, cd will move to the top workspace on the stack by popping off all workspaces.

        Examples:

          cd Foo
          cd Foo.new
          cd @ivar
          cd ..
          cd
      HELP

      def execute(arg)
        case arg
        when ".."
          irb_context.pop_workspace
        when ""
          # TODO: decide what workspace commands should be kept, and underlying APIs should look like,
          # and perhaps add a new API to clear the workspace stack.
          prev_workspace = irb_context.pop_workspace
          while prev_workspace
            prev_workspace = irb_context.pop_workspace
          end
        else
          begin
            obj = eval(arg, irb_context.workspace.binding)
            irb_context.push_workspace(obj)
          rescue StandardError => e
            warn "Error: #{e}"
          end
        end
      end
    end
  end
end
