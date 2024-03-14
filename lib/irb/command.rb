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
    EXCB = ExtendCommandBundle # :nodoc:

    # See #install_alias_method.
    NO_OVERRIDE = 0
    # See #install_alias_method.
    OVERRIDE_PRIVATE_ONLY = 0x01
    # See #install_alias_method.
    OVERRIDE_ALL = 0x02

    # Displays current configuration.
    #
    # Modifying the configuration is achieved by sending a message to IRB.conf.
    def irb_context
      IRB.CurrentContext
    end

    @ALIASES = [
      [:context, :irb_context, NO_OVERRIDE],
      [:conf, :irb_context, NO_OVERRIDE],
    ]


    @EXTEND_COMMANDS = [
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

    # Installs the default irb commands.
    def self.install_extend_commands
      for args in @EXTEND_COMMANDS
        def_extend_command(*args)
      end
    end

    # Evaluate the given +cmd_name+ on the given +cmd_class+ Class.
    #
    # Will also define any given +aliases+ for the method.
    #
    # The optional +load_file+ parameter will be required within the method
    # definition.
    def self.def_extend_command(cmd_name, cmd_class, load_file, *aliases)
      case cmd_class
      when Symbol
        cmd_class = cmd_class.id2name
      when String
      when Class
        cmd_class = cmd_class.name
      end

      line = __LINE__; eval %[
        def #{cmd_name}(*opts, **kwargs, &b)
          Kernel.require_relative "#{load_file}"
          ::IRB::Command::#{cmd_class}.execute(irb_context, *opts, **kwargs, &b)
        end
      ], nil, __FILE__, line

      for ali, flag in aliases
        @ALIASES.push [ali, cmd_name, flag]
      end
    end

    # Installs alias methods for the default irb commands, see
    # ::install_extend_commands.
    def install_alias_method(to, from, override = NO_OVERRIDE)
      to = to.id2name unless to.kind_of?(String)
      from = from.id2name unless from.kind_of?(String)

      if override == OVERRIDE_ALL or
          (override == OVERRIDE_PRIVATE_ONLY) && !respond_to?(to) or
          (override == NO_OVERRIDE) &&  !respond_to?(to, true)
        target = self
        (class << self; self; end).instance_eval{
          if target.respond_to?(to, true) &&
            !target.respond_to?(EXCB.irb_original_method_name(to), true)
            alias_method(EXCB.irb_original_method_name(to), to)
          end
          alias_method to, from
        }
      else
        Kernel.warn "irb: warn: can't alias #{to} from #{from}.\n"
      end
    end

    def self.irb_original_method_name(method_name) # :nodoc:
      "irb_" + method_name + "_org"
    end

    # Installs alias methods for the default irb commands on the given object
    # using #install_alias_method.
    def self.extend_object(obj)
      unless (class << obj; ancestors; end).include?(EXCB)
        super
        for ali, com, flg in @ALIASES
          obj.install_alias_method(ali, com, flg)
        end
      end
    end

    install_extend_commands
  end
end
