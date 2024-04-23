# frozen_string_literal: true

module IRB
  module Command
    class Help < Base
      category "Help"
      description "List all available commands. Use `help <command>` to get information about a specific command."

      def execute(command_name)
        content =
          if command_name.empty?
            help_message
          else
            if command_class = Command.load_command(command_name)
              command_class.help_message || command_class.description
            else
              "Can't find command `#{command_name}`. Please check the command name and try again.\n\n"
            end
          end
        Pager.page_content(content)
      end

      private

      def help_message
        commands_info = IRB::Command.all_commands_info
        helper_methods_info = IRB::HelperMethod.all_helper_methods_info
        commands_grouped_by_categories = commands_info.group_by { |cmd| cmd[:category] }
        commands_grouped_by_categories["Helper methods"] = helper_methods_info

        user_aliases = irb_context.instance_variable_get(:@user_aliases)

        commands_grouped_by_categories["Aliases"] = user_aliases.map do |alias_name, target|
          { display_name: alias_name, description: "Alias for `#{target}`" }
        end

        if irb_context.with_debugger
          # Remove the original "Debugging" category
          commands_grouped_by_categories.delete("Debugging")
          # Add an empty "Debugging (from debug.gem)" category at the end
          commands_grouped_by_categories["Debugging (from debug.gem)"] = []
        end

        longest_cmd_name_length = commands_info.map { |c| c[:display_name].length }.max

        output = StringIO.new

        help_cmds = commands_grouped_by_categories.delete("Help")

        add_category_to_output("Help", help_cmds, output, longest_cmd_name_length)

        commands_grouped_by_categories.each do |category, cmds|
          add_category_to_output(category, cmds, output, longest_cmd_name_length)
        end

        # Append the debugger help at the end
        if irb_context.with_debugger
          output.puts DEBUGGER__.help
        end

        output.string
      end

      def add_category_to_output(category, cmds, output, longest_cmd_name_length)
        output.puts Color.colorize(category, [:BOLD])

        cmds.each do |cmd|
          output.puts "  #{cmd[:display_name].to_s.ljust(longest_cmd_name_length)}    #{cmd[:description]}"
        end

        output.puts
      end
    end
  end
end
