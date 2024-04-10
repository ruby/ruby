# frozen_string_literal: true
#
#   irb/command.rb - irb command
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative "command/base"

module IRB # :nodoc:
  module Command; end
  ExtendCommand = Command

  # Installs the default irb extensions command bundle.
  module ExtendCommandBundle
    # See ExtendCommandBundle.execute_as_command?.
    NO_OVERRIDE = 0
    OVERRIDE_PRIVATE_ONLY = 0x01
    OVERRIDE_ALL = 0x02

    @EXTEND_COMMANDS = [
      [
        :irb_context, :Context, "command/context",
        [:context, NO_OVERRIDE],
        [:conf, NO_OVERRIDE],
      ],
      [
        :irb_exit, :Exit, "command/exit",
        [:exit, OVERRIDE_PRIVATE_ONLY],
        [:quit, OVERRIDE_PRIVATE_ONLY],
        [:irb_quit, OVERRIDE_PRIVATE_ONLY],
      ],
      [
        :irb_exit!, :ForceExit, "command/force_exit",
        [:exit!, OVERRIDE_PRIVATE_ONLY],
      ],

      [
        :irb_current_working_workspace, :CurrentWorkingWorkspace, "command/chws",
        [:cwws, NO_OVERRIDE],
        [:pwws, NO_OVERRIDE],
        [:irb_print_working_workspace, OVERRIDE_ALL],
        [:irb_cwws, OVERRIDE_ALL],
        [:irb_pwws, OVERRIDE_ALL],
        [:irb_current_working_binding, OVERRIDE_ALL],
        [:irb_print_working_binding, OVERRIDE_ALL],
        [:irb_cwb, OVERRIDE_ALL],
        [:irb_pwb, OVERRIDE_ALL],
      ],
      [
        :irb_change_workspace, :ChangeWorkspace, "command/chws",
        [:chws, NO_OVERRIDE],
        [:cws, NO_OVERRIDE],
        [:irb_chws, OVERRIDE_ALL],
        [:irb_cws, OVERRIDE_ALL],
        [:irb_change_binding, OVERRIDE_ALL],
        [:irb_cb, OVERRIDE_ALL],
        [:cb, NO_OVERRIDE],
      ],

      [
        :irb_workspaces, :Workspaces, "command/pushws",
        [:workspaces, NO_OVERRIDE],
        [:irb_bindings, OVERRIDE_ALL],
        [:bindings, NO_OVERRIDE],
      ],
      [
        :irb_push_workspace, :PushWorkspace, "command/pushws",
        [:pushws, NO_OVERRIDE],
        [:irb_pushws, OVERRIDE_ALL],
        [:irb_push_binding, OVERRIDE_ALL],
        [:irb_pushb, OVERRIDE_ALL],
        [:pushb, NO_OVERRIDE],
      ],
      [
        :irb_pop_workspace, :PopWorkspace, "command/pushws",
        [:popws, NO_OVERRIDE],
        [:irb_popws, OVERRIDE_ALL],
        [:irb_pop_binding, OVERRIDE_ALL],
        [:irb_popb, OVERRIDE_ALL],
        [:popb, NO_OVERRIDE],
      ],

      [
        :irb_load, :Load, "command/load"],
      [
        :irb_require, :Require, "command/load"],
      [
        :irb_source, :Source, "command/load",
        [:source, NO_OVERRIDE],
      ],

      [
        :irb, :IrbCommand, "command/subirb"],
      [
        :irb_jobs, :Jobs, "command/subirb",
        [:jobs, NO_OVERRIDE],
      ],
      [
        :irb_fg, :Foreground, "command/subirb",
        [:fg, NO_OVERRIDE],
      ],
      [
        :irb_kill, :Kill, "command/subirb",
        [:kill, OVERRIDE_PRIVATE_ONLY],
      ],

      [
        :irb_debug, :Debug, "command/debug",
        [:debug, NO_OVERRIDE],
      ],
      [
        :irb_edit, :Edit, "command/edit",
        [:edit, NO_OVERRIDE],
      ],
      [
        :irb_break, :Break, "command/break",
      ],
      [
        :irb_catch, :Catch, "command/catch",
      ],
      [
        :irb_next, :Next, "command/next"
      ],
      [
        :irb_delete, :Delete, "command/delete",
        [:delete, NO_OVERRIDE],
      ],
      [
        :irb_step, :Step, "command/step",
        [:step, NO_OVERRIDE],
      ],
      [
        :irb_continue, :Continue, "command/continue",
        [:continue, NO_OVERRIDE],
      ],
      [
        :irb_finish, :Finish, "command/finish",
        [:finish, NO_OVERRIDE],
      ],
      [
        :irb_backtrace, :Backtrace, "command/backtrace",
        [:backtrace, NO_OVERRIDE],
        [:bt, NO_OVERRIDE],
      ],
      [
        :irb_debug_info, :Info, "command/info",
        [:info, NO_OVERRIDE],
      ],

      [
        :irb_help, :Help, "command/help",
        [:help, NO_OVERRIDE],
        [:show_cmds, NO_OVERRIDE],
      ],

      [
        :irb_show_doc, :ShowDoc, "command/show_doc",
        [:show_doc, NO_OVERRIDE],
      ],

      [
        :irb_info, :IrbInfo, "command/irb_info"
      ],

      [
        :irb_ls, :Ls, "command/ls",
        [:ls, NO_OVERRIDE],
      ],

      [
        :irb_measure, :Measure, "command/measure",
        [:measure, NO_OVERRIDE],
      ],

      [
        :irb_show_source, :ShowSource, "command/show_source",
        [:show_source, NO_OVERRIDE],
      ],
      [
        :irb_whereami, :Whereami, "command/whereami",
        [:whereami, NO_OVERRIDE],
      ],
      [
        :irb_history, :History, "command/history",
        [:history, NO_OVERRIDE],
        [:hist, NO_OVERRIDE],
      ],

      [
        :irb_disable_irb, :DisableIrb, "command/disable_irb",
        [:disable_irb, NO_OVERRIDE],
      ],
    ]

    def self.command_override_policies
      @@command_override_policies ||= @EXTEND_COMMANDS.flat_map do |cmd_name, cmd_class, load_file, *aliases|
        [[cmd_name, OVERRIDE_ALL]] + aliases
      end.to_h
    end

    def self.execute_as_command?(name, public_method:, private_method:)
      case command_override_policies[name]
      when OVERRIDE_ALL
        true
      when OVERRIDE_PRIVATE_ONLY
        !public_method
      when NO_OVERRIDE
        !public_method && !private_method
      end
    end

    def self.command_names
      command_override_policies.keys.map(&:to_s)
    end

    @@commands = []

    def self.all_commands_info
      return @@commands unless @@commands.empty?
      user_aliases = IRB.CurrentContext.command_aliases.each_with_object({}) do |(alias_name, target), result|
        result[target] ||= []
        result[target] << alias_name
      end

      @EXTEND_COMMANDS.each do |cmd_name, cmd_class, load_file, *aliases|
        if !defined?(Command) || !Command.const_defined?(cmd_class, false)
          require_relative load_file
        end

        klass = Command.const_get(cmd_class, false)
        aliases = aliases.map { |a| a.first }

        if additional_aliases = user_aliases[cmd_name]
          aliases += additional_aliases
        end

        display_name = aliases.shift || cmd_name
        @@commands << { display_name: display_name, description: klass.description, category: klass.category }
      end

      @@commands
    end

    # Convert a command name to its implementation class if such command exists
    def self.load_command(command)
      command = command.to_sym
      @EXTEND_COMMANDS.each do |cmd_name, cmd_class, load_file, *aliases|
        next if cmd_name != command && aliases.all? { |alias_name, _| alias_name != command }

        if !defined?(Command) || !Command.const_defined?(cmd_class, false)
          require_relative load_file
        end
        return Command.const_get(cmd_class, false)
      end
      nil
    end

    def self.def_extend_command(cmd_name, cmd_class, load_file, *aliases)
      @EXTEND_COMMANDS.delete_if { |name,| name == cmd_name }
      @EXTEND_COMMANDS << [cmd_name, cmd_class, load_file, *aliases]

      # Just clear memoized values
      @@commands = []
      @@command_override_policies = nil
    end
  end
end
