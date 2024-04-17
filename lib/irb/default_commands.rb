# frozen_string_literal: true

require_relative "command"
require_relative "command/internal_helpers"
require_relative "command/context"
require_relative "command/exit"
require_relative "command/force_exit"
require_relative "command/chws"
require_relative "command/pushws"
require_relative "command/subirb"
require_relative "command/load"
require_relative "command/debug"
require_relative "command/edit"
require_relative "command/break"
require_relative "command/catch"
require_relative "command/next"
require_relative "command/delete"
require_relative "command/step"
require_relative "command/continue"
require_relative "command/finish"
require_relative "command/backtrace"
require_relative "command/info"
require_relative "command/help"
require_relative "command/show_doc"
require_relative "command/irb_info"
require_relative "command/ls"
require_relative "command/measure"
require_relative "command/show_source"
require_relative "command/whereami"
require_relative "command/history"

module IRB
  ExtendCommand = Command

  # Installs the default irb extensions command bundle.
  module ExtendCommandBundle
    # See #install_alias_method.
    NO_OVERRIDE = 0
    # See #install_alias_method.
    OVERRIDE_PRIVATE_ONLY = 0x01
    # See #install_alias_method.
    OVERRIDE_ALL = 0x02

    Command._register_with_aliases(:irb_context, Command::Context,
      [
        [:context, NO_OVERRIDE],
        [:conf, NO_OVERRIDE],
      ],
    )

    Command._register_with_aliases(:irb_exit, Command::Exit,
      [:exit, OVERRIDE_PRIVATE_ONLY],
      [:quit, OVERRIDE_PRIVATE_ONLY],
      [:irb_quit, OVERRIDE_PRIVATE_ONLY]
    )

    Command._register_with_aliases(:irb_exit!, Command::ForceExit,
      [:exit!, OVERRIDE_PRIVATE_ONLY]
    )

    Command._register_with_aliases(:irb_current_working_workspace, Command::CurrentWorkingWorkspace,
      [:cwws, NO_OVERRIDE],
      [:pwws, NO_OVERRIDE],
      [:irb_print_working_workspace, OVERRIDE_ALL],
      [:irb_cwws, OVERRIDE_ALL],
      [:irb_pwws, OVERRIDE_ALL],
      [:irb_current_working_binding, OVERRIDE_ALL],
      [:irb_print_working_binding, OVERRIDE_ALL],
      [:irb_cwb, OVERRIDE_ALL],
      [:irb_pwb, OVERRIDE_ALL],
    )

    Command._register_with_aliases(:irb_change_workspace, Command::ChangeWorkspace,
      [:chws, NO_OVERRIDE],
      [:cws, NO_OVERRIDE],
      [:irb_chws, OVERRIDE_ALL],
      [:irb_cws, OVERRIDE_ALL],
      [:irb_change_binding, OVERRIDE_ALL],
      [:irb_cb, OVERRIDE_ALL],
      [:cb, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_workspaces, Command::Workspaces,
      [:workspaces, NO_OVERRIDE],
      [:irb_bindings, OVERRIDE_ALL],
      [:bindings, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_push_workspace, Command::PushWorkspace,
      [:pushws, NO_OVERRIDE],
      [:irb_pushws, OVERRIDE_ALL],
      [:irb_push_binding, OVERRIDE_ALL],
      [:irb_pushb, OVERRIDE_ALL],
      [:pushb, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_pop_workspace, Command::PopWorkspace,
      [:popws, NO_OVERRIDE],
      [:irb_popws, OVERRIDE_ALL],
      [:irb_pop_binding, OVERRIDE_ALL],
      [:irb_popb, OVERRIDE_ALL],
      [:popb, NO_OVERRIDE],
    )

    Command._register_with_aliases(:irb_load, Command::Load)
    Command._register_with_aliases(:irb_require, Command::Require)
    Command._register_with_aliases(:irb_source, Command::Source,
      [:source, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb, Command::IrbCommand)
    Command._register_with_aliases(:irb_jobs, Command::Jobs,
      [:jobs, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_fg, Command::Foreground,
      [:fg, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_kill, Command::Kill,
      [:kill, OVERRIDE_PRIVATE_ONLY]
    )

    Command._register_with_aliases(:irb_debug, Command::Debug,
      [:debug, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_edit, Command::Edit,
      [:edit, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_break, Command::Break)
    Command._register_with_aliases(:irb_catch, Command::Catch)
    Command._register_with_aliases(:irb_next, Command::Next)
    Command._register_with_aliases(:irb_delete, Command::Delete,
      [:delete, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_step, Command::Step,
      [:step, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_continue, Command::Continue,
      [:continue, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_finish, Command::Finish,
      [:finish, NO_OVERRIDE]
    )
    Command._register_with_aliases(:irb_backtrace, Command::Backtrace,
      [:backtrace, NO_OVERRIDE],
      [:bt, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_debug_info, Command::Info,
      [:info, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_help, Command::Help,
      [:help, NO_OVERRIDE],
      [:show_cmds, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_show_doc, Command::ShowDoc,
      [:show_doc, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_info, Command::IrbInfo)

    Command._register_with_aliases(:irb_ls, Command::Ls,
      [:ls, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_measure, Command::Measure,
      [:measure, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_show_source, Command::ShowSource,
      [:show_source, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_whereami, Command::Whereami,
      [:whereami, NO_OVERRIDE]
    )

    Command._register_with_aliases(:irb_history, Command::History,
      [:history, NO_OVERRIDE],
      [:hist, NO_OVERRIDE]
    )

    def self.all_commands_info
      user_aliases = IRB.CurrentContext.command_aliases.each_with_object({}) do |(alias_name, target), result|
        result[target] ||= []
        result[target] << alias_name
      end

      Command.commands.map do |command_name, (command_class, aliases)|
        aliases = aliases.map { |a| a.first }

        if additional_aliases = user_aliases[command_name]
          aliases += additional_aliases
        end

        display_name = aliases.shift || command_name
        {
          display_name: display_name,
          description: command_class.description,
          category: command_class.category
        }
      end
    end

    def self.command_override_policies
      @@command_override_policies ||= Command.commands.flat_map do |cmd_name, (cmd_class, aliases)|
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

    # Convert a command name to its implementation class if such command exists
    def self.load_command(command)
      command = command.to_sym
      Command.commands.each do |command_name, (command_class, aliases)|
        if command_name == command || aliases.any? { |alias_name, _| alias_name == command }
          return command_class
        end
      end
      nil
    end

    # Deprecated. Doesn't have any effect.
    @EXTEND_COMMANDS = []

    # Drepcated. Use Command.regiser instead.
    def self.def_extend_command(cmd_name, cmd_class, _, *aliases)
      Command._register_with_aliases(cmd_name, cmd_class, *aliases)
      @@command_override_policies = nil
    end
  end
end
