# frozen_string_literal: false
#
#   irb.rb - irb main module
#       by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require "ripper"
require "reline"

require_relative "irb/init"
require_relative "irb/context"
require_relative "irb/extend-command"

require_relative "irb/ruby-lex"
require_relative "irb/statement"
require_relative "irb/input-method"
require_relative "irb/locale"
require_relative "irb/color"

require_relative "irb/version"
require_relative "irb/easter-egg"
require_relative "irb/debug"
require_relative "irb/pager"

# IRB stands for "interactive Ruby" and is a tool to interactively execute Ruby
# expressions read from the standard input.
#
# The +irb+ command from your shell will start the interpreter.
#
# == Usage
#
# Use of irb is easy if you know Ruby.
#
# When executing irb, prompts are displayed as follows. Then, enter the Ruby
# expression. An input is executed when it is syntactically complete.
#
#     $ irb
#     irb(main):001:0> 1+2
#     #=> 3
#     irb(main):002:0> class Foo
#     irb(main):003:1>  def foo
#     irb(main):004:2>    print 1
#     irb(main):005:2>  end
#     irb(main):006:1> end
#     #=> nil
#
# The singleline editor module or multiline editor module can be used with irb.
# Use of multiline editor is default if it's installed.
#
# == Command line options
#
#   :include: ./irb/lc/help-message
#
# == Commands
#
# The following commands are available on IRB.
#
# * cwws
#   * Show the current workspace.
# * cb, cws, chws
#   * Change the current workspace to an object.
# * bindings, workspaces
#   * Show workspaces.
# * pushb, pushws
#   * Push an object to the workspace stack.
# * popb, popws
#   * Pop a workspace from the workspace stack.
# * load
#   * Load a Ruby file.
# * require
#   * Require a Ruby file.
# * source
#   * Loads a given file in the current session.
# * irb
#   * Start a child IRB.
# * jobs
#   * List of current sessions.
# * fg
#   * Switches to the session of the given number.
# * kill
#   * Kills the session with the given number.
# * help
#   * Enter the mode to look up RI documents.
# * irb_info
#   * Show information about IRB.
# * ls
#   * Show methods, constants, and variables.
#     -g [query] or -G [query] allows you to filter out the output.
# * measure
#   * measure enables the mode to measure processing time. measure :off disables it.
# * $, show_source
#   * Show the source code of a given method or constant.
# * @, whereami
#   * Show the source code around binding.irb again.
# * debug
#   * Start the debugger of debug.gem.
# * break, delete, next, step, continue, finish, backtrace, info, catch
#   * Start the debugger of debug.gem and run the command on it.
#
# == Configuration
#
# IRB reads a personal initialization file when it's invoked.
# IRB searches a file in the following order and loads the first one found.
#
# * <tt>$IRBRC</tt> (if <tt>$IRBRC</tt> is set)
# * <tt>$XDG_CONFIG_HOME/irb/irbrc</tt> (if <tt>$XDG_CONFIG_HOME</tt> is set)
# * <tt>~/.irbrc</tt>
# * +.config/irb/irbrc+
# * +.irbrc+
# * +irb.rc+
# * +_irbrc+
# * <code>$irbrc</code>
#
# The following are alternatives to the command line options. To use them type
# as follows in an +irb+ session:
#
#     IRB.conf[:IRB_NAME]="irb"
#     IRB.conf[:INSPECT_MODE]=nil
#     IRB.conf[:IRB_RC] = nil
#     IRB.conf[:BACK_TRACE_LIMIT]=16
#     IRB.conf[:USE_LOADER] = false
#     IRB.conf[:USE_MULTILINE] = nil
#     IRB.conf[:USE_SINGLELINE] = nil
#     IRB.conf[:USE_COLORIZE] = true
#     IRB.conf[:USE_TRACER] = false
#     IRB.conf[:USE_AUTOCOMPLETE] = true
#     IRB.conf[:IGNORE_SIGINT] = true
#     IRB.conf[:IGNORE_EOF] = false
#     IRB.conf[:PROMPT_MODE] = :DEFAULT
#     IRB.conf[:PROMPT] = {...}
#
# === Auto indentation
#
# To disable auto-indent mode in irb, add the following to your +.irbrc+:
#
#     IRB.conf[:AUTO_INDENT] = false
#
# === Autocompletion
#
# To disable autocompletion for irb, add the following to your +.irbrc+:
#
#     IRB.conf[:USE_AUTOCOMPLETE] = false
#
# To enable enhanced completion using type information, add the following to your +.irbrc+:
#
#     IRB.conf[:COMPLETOR] = :type
#
# === History
#
# By default, irb will store the last 1000 commands you used in
# <code>IRB.conf[:HISTORY_FILE]</code> (<code>~/.irb_history</code> by default).
#
# If you want to disable history, add the following to your +.irbrc+:
#
#     IRB.conf[:SAVE_HISTORY] = nil
#
# See IRB::Context#save_history= for more information.
#
# The history of _results_ of commands evaluated is not stored by default,
# but can be turned on to be stored with this +.irbrc+ setting:
#
#     IRB.conf[:EVAL_HISTORY] = <number>
#
# See IRB::Context#eval_history= and EvalHistory class. The history of command
# results is not permanently saved in any file.
#
# == Customizing the IRB Prompt
#
# In order to customize the prompt, you can change the following Hash:
#
#     IRB.conf[:PROMPT]
#
# This example can be used in your +.irbrc+
#
#     IRB.conf[:PROMPT][:MY_PROMPT] = { # name of prompt mode
#       :AUTO_INDENT => false,          # disables auto-indent mode
#       :PROMPT_I =>  ">> ",		# simple prompt
#       :PROMPT_S => nil,		# prompt for continuated strings
#       :PROMPT_C => nil,		# prompt for continuated statement
#       :RETURN => "    ==>%s\n"	# format to return value
#     }
#
#     IRB.conf[:PROMPT_MODE] = :MY_PROMPT
#
# Or, invoke irb with the above prompt mode by:
#
#     irb --prompt my-prompt
#
# Constants +PROMPT_I+, +PROMPT_S+ and +PROMPT_C+ specify the format. In the
# prompt specification, some special strings are available:
#
#     %N    # command name which is running
#     %m    # to_s of main object (self)
#     %M    # inspect of main object (self)
#     %l    # type of string(", ', /, ]), `]' is inner %w[...]
#     %NNi  # indent level. NN is digits and means as same as printf("%NNd").
#           # It can be omitted
#     %NNn  # line number.
#     %%    # %
#
# For instance, the default prompt mode is defined as follows:
#
#     IRB.conf[:PROMPT_MODE][:DEFAULT] = {
#       :PROMPT_I => "%N(%m):%03n> ",
#       :PROMPT_S => "%N(%m):%03n%l ",
#       :PROMPT_C => "%N(%m):%03n* ",
#       :RETURN => "%s\n" # used to printf
#     }
#
# irb comes with a number of available modes:
#
#   # :NULL:
#   #   :PROMPT_I:
#   #   :PROMPT_S:
#   #   :PROMPT_C:
#   #   :RETURN: |
#   #     %s
#   # :DEFAULT:
#   #   :PROMPT_I: ! '%N(%m):%03n> '
#   #   :PROMPT_S: ! '%N(%m):%03n%l '
#   #   :PROMPT_C: ! '%N(%m):%03n* '
#   #   :RETURN: |
#   #     => %s
#   # :CLASSIC:
#   #   :PROMPT_I: ! '%N(%m):%03n:%i> '
#   #   :PROMPT_S: ! '%N(%m):%03n:%i%l '
#   #   :PROMPT_C: ! '%N(%m):%03n:%i* '
#   #   :RETURN: |
#   #     %s
#   # :SIMPLE:
#   #   :PROMPT_I: ! '>> '
#   #   :PROMPT_S:
#   #   :PROMPT_C: ! '?> '
#   #   :RETURN: |
#   #     => %s
#   # :INF_RUBY:
#   #   :PROMPT_I: ! '%N(%m):%03n> '
#   #   :PROMPT_S:
#   #   :PROMPT_C:
#   #   :RETURN: |
#   #     %s
#   #   :AUTO_INDENT: true
#   # :XMP:
#   #   :PROMPT_I:
#   #   :PROMPT_S:
#   #   :PROMPT_C:
#   #   :RETURN: |2
#   #         ==>%s
#
# == Restrictions
#
# Because irb evaluates input immediately after it is syntactically complete,
# the results may be slightly different than directly using Ruby.
#
# == IRB Sessions
#
# IRB has a special feature, that allows you to manage many sessions at once.
#
# You can create new sessions with Irb.irb, and get a list of current sessions
# with the +jobs+ command in the prompt.
#
# === Commands
#
# JobManager provides commands to handle the current sessions:
#
#   jobs    # List of current sessions
#   fg      # Switches to the session of the given number
#   kill    # Kills the session with the given number
#
# The +exit+ command, or ::irb_exit, will quit the current session and call any
# exit hooks with IRB.irb_at_exit.
#
# A few commands for loading files within the session are also available:
#
# +source+::
#   Loads a given file in the current session and displays the source lines,
#   see IrbLoader#source_file
# +irb_load+::
#   Loads the given file similarly to Kernel#load, see IrbLoader#irb_load
# +irb_require+::
#   Loads the given file similarly to Kernel#require
#
# === Configuration
#
# The command line options, or IRB.conf, specify the default behavior of
# Irb.irb.
#
# On the other hand, each conf in IRB@Command+line+options is used to
# individually configure IRB.irb.
#
# If a proc is set for <code>IRB.conf[:IRB_RC]</code>, its will be invoked after execution
# of that proc with the context of the current session as its argument. Each
# session can be configured using this mechanism.
#
# === Session variables
#
# There are a few variables in every Irb session that can come in handy:
#
# <code>_</code>::
#   The value command executed, as a local variable
# <code>__</code>::
#   The history of evaluated commands. Available only if
#   <code>IRB.conf[:EVAL_HISTORY]</code> is not +nil+ (which is the default).
#   See also IRB::Context#eval_history= and IRB::History.
# <code>__[line_no]</code>::
#   Returns the evaluation value at the given line number, +line_no+.
#   If +line_no+ is a negative, the return value +line_no+ many lines before
#   the most recent return value.
#
# === Example using IRB Sessions
#
#   # invoke a new session
#   irb(main):001:0> irb
#   # list open sessions
#   irb.1(main):001:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : stop)
#     #1->irb#1 on main (#<Thread:0x40125d64> : running)
#
#   # change the active session
#   irb.1(main):002:0> fg 0
#   # define class Foo in top-level session
#   irb(main):002:0> class Foo;end
#   # invoke a new session with the context of Foo
#   irb(main):003:0> irb Foo
#   # define Foo#foo
#   irb.2(Foo):001:0> def foo
#   irb.2(Foo):002:1>   print 1
#   irb.2(Foo):003:1> end
#
#   # change the active session
#   irb.2(Foo):004:0> fg 0
#   # list open sessions
#   irb(main):004:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : running)
#     #1->irb#1 on main (#<Thread:0x40125d64> : stop)
#     #2->irb#2 on Foo (#<Thread:0x4011d54c> : stop)
#   # check if Foo#foo is available
#   irb(main):005:0> Foo.instance_methods #=> [:foo, ...]
#
#   # change the active session
#   irb(main):006:0> fg 2
#   # define Foo#bar in the context of Foo
#   irb.2(Foo):005:0> def bar
#   irb.2(Foo):006:1>  print "bar"
#   irb.2(Foo):007:1> end
#   irb.2(Foo):010:0>  Foo.instance_methods #=> [:bar, :foo, ...]
#
#   # change the active session
#   irb.2(Foo):011:0> fg 0
#   irb(main):007:0> f = Foo.new  #=> #<Foo:0x4010af3c>
#   # invoke a new session with the context of f (instance of Foo)
#   irb(main):008:0> irb f
#   # list open sessions
#   irb.3(<Foo:0x4010af3c>):001:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : stop)
#     #1->irb#1 on main (#<Thread:0x40125d64> : stop)
#     #2->irb#2 on Foo (#<Thread:0x4011d54c> : stop)
#     #3->irb#3 on #<Foo:0x4010af3c> (#<Thread:0x4010a1e0> : running)
#   # evaluate f.foo
#   irb.3(<Foo:0x4010af3c>):002:0> foo #=> 1 => nil
#   # evaluate f.bar
#   irb.3(<Foo:0x4010af3c>):003:0> bar #=> bar => nil
#   # kill jobs 1, 2, and 3
#   irb.3(<Foo:0x4010af3c>):004:0> kill 1, 2, 3
#   # list open sessions, should only include main session
#   irb(main):009:0> jobs
#     #0->irb on main (#<Thread:0x400fb7e4> : running)
#   # quit irb
#   irb(main):010:0> exit
module IRB

  # An exception raised by IRB.irb_abort
  class Abort < Exception;end

  # The current IRB::Context of the session, see IRB.conf
  #
  #   irb
  #   irb(main):001:0> IRB.CurrentContext.irb_name = "foo"
  #   foo(main):002:0> IRB.conf[:MAIN_CONTEXT].irb_name #=> "foo"
  def IRB.CurrentContext
    IRB.conf[:MAIN_CONTEXT]
  end

  # Initializes IRB and creates a new Irb.irb object at the +TOPLEVEL_BINDING+
  def IRB.start(ap_path = nil)
    STDOUT.sync = true
    $0 = File::basename(ap_path, ".rb") if ap_path

    IRB.setup(ap_path)

    if @CONF[:SCRIPT]
      irb = Irb.new(nil, @CONF[:SCRIPT])
    else
      irb = Irb.new
    end
    irb.run(@CONF)
  end

  # Quits irb
  def IRB.irb_exit(irb, ret)
    throw :IRB_EXIT, ret
  end

  # Aborts then interrupts irb.
  #
  # Will raise an Abort exception, or the given +exception+.
  def IRB.irb_abort(irb, exception = Abort)
    irb.context.thread.raise exception, "abort then interrupt!"
  end

  class Irb
    # Note: instance and index assignment expressions could also be written like:
    # "foo.bar=(1)" and "foo.[]=(1, bar)", when expressed that way, the former
    # be parsed as :assign and echo will be suppressed, but the latter is
    # parsed as a :method_add_arg and the output won't be suppressed

    PROMPT_MAIN_TRUNCATE_LENGTH = 32
    PROMPT_MAIN_TRUNCATE_OMISSION = '...'.freeze
    CONTROL_CHARACTERS_PATTERN = "\x00-\x1F".freeze

    # Returns the current context of this irb session
    attr_reader :context
    # The lexer used by this irb session
    attr_accessor :scanner

    # Creates a new irb session
    def initialize(workspace = nil, input_method = nil)
      @context = Context.new(self, workspace, input_method)
      @context.workspace.load_commands_to_main
      @signal_status = :IN_IRB
      @scanner = RubyLex.new
      @line_no = 1
    end

    # A hook point for `debug` command's breakpoint after :IRB_EXIT as well as its clean-up
    def debug_break
      # it means the debug integration has been activated
      if defined?(DEBUGGER__) && DEBUGGER__.respond_to?(:capture_frames_without_irb)
        # after leaving this initial breakpoint, revert the capture_frames patch
        DEBUGGER__.singleton_class.send(:alias_method, :capture_frames, :capture_frames_without_irb)
        # and remove the redundant method
        DEBUGGER__.singleton_class.send(:undef_method, :capture_frames_without_irb)
      end
    end

    def debug_readline(binding)
      workspace = IRB::WorkSpace.new(binding)
      context.workspace = workspace
      context.workspace.load_commands_to_main
      @line_no += 1

      # When users run:
      # 1. Debugging commands, like `step 2`
      # 2. Any input that's not irb-command, like `foo = 123`
      #
      # Irb#eval_input will simply return the input, and we need to pass it to the debugger.
      input = if IRB.conf[:SAVE_HISTORY] && context.io.support_history_saving?
        # Previous IRB session's history has been saved when `Irb#run` is exited
        # We need to make sure the saved history is not saved again by reseting the counter
        context.io.reset_history_counter

        begin
          eval_input
        ensure
          context.io.save_history
        end
      else
        eval_input
      end

      if input&.include?("\n")
        @line_no += input.count("\n") - 1
      end

      input
    end

    def run(conf = IRB.conf)
      in_nested_session = !!conf[:MAIN_CONTEXT]
      conf[:IRB_RC].call(context) if conf[:IRB_RC]
      conf[:MAIN_CONTEXT] = context

      save_history = !in_nested_session && conf[:SAVE_HISTORY] && context.io.support_history_saving?

      if save_history
        context.io.load_history
      end

      prev_trap = trap("SIGINT") do
        signal_handle
      end

      begin
        catch(:IRB_EXIT) do
          eval_input
        end
      ensure
        trap("SIGINT", prev_trap)
        conf[:AT_EXIT].each{|hook| hook.call}
        context.io.save_history if save_history
      end
    end

    # Evaluates input for this session.
    def eval_input
      configure_io

      each_top_level_statement do |statement, line_no|
        signal_status(:IN_EVAL) do
          begin
            # If the integration with debugger is activated, we return certain input if it should be dealt with by debugger
            if @context.with_debugger && statement.should_be_handled_by_debugger?
              return statement.code
            end

            @context.evaluate(statement.evaluable_code, line_no)

            if @context.echo? && !statement.suppresses_echo?
              if statement.is_assignment?
                if @context.echo_on_assignment?
                  output_value(@context.echo_on_assignment? == :truncate)
                end
              else
                output_value
              end
            end
          rescue SystemExit, SignalException
            raise
          rescue Interrupt, Exception => exc
            handle_exception(exc)
            @context.workspace.local_variable_set(:_, exc)
          end
        end
      end
    end

    def read_input(prompt)
      signal_status(:IN_INPUT) do
        @context.io.prompt = prompt
        if l = @context.io.gets
          print l if @context.verbose?
        else
          if @context.ignore_eof? and @context.io.readable_after_eof?
            l = "\n"
            if @context.verbose?
              printf "Use \"exit\" to leave %s\n", @context.ap_name
            end
          else
            print "\n" if @context.prompting?
          end
        end
        l
      end
    end

    def readmultiline
      prompt = generate_prompt([], false, 0)

      # multiline
      return read_input(prompt) if @context.io.respond_to?(:check_termination)

      # nomultiline
      code = ''
      line_offset = 0
      loop do
        line = read_input(prompt)
        unless line
          return code.empty? ? nil : code
        end

        code << line

        # Accept any single-line input for symbol aliases or commands that transform args
        return code if single_line_command?(code)

        tokens, opens, terminated = @scanner.check_code_state(code, local_variables: @context.local_variables)
        return code if terminated

        line_offset += 1
        continue = @scanner.should_continue?(tokens)
        prompt = generate_prompt(opens, continue, line_offset)
      end
    end

    def each_top_level_statement
      loop do
        code = readmultiline
        break unless code

        if code != "\n"
          yield build_statement(code), @line_no
        end
        @line_no += code.count("\n")
      rescue RubyLex::TerminateLineInput
      end
    end

    def build_statement(code)
      code.force_encoding(@context.io.encoding)
      command_or_alias, arg = code.split(/\s/, 2)
      # Transform a non-identifier alias (@, $) or keywords (next, break)
      command_name = @context.command_aliases[command_or_alias.to_sym]
      command = command_name || command_or_alias
      command_class = ExtendCommandBundle.load_command(command)

      if command_class
        Statement::Command.new(code, command, arg, command_class)
      else
        is_assignment_expression = @scanner.assignment_expression?(code, local_variables: @context.local_variables)
        Statement::Expression.new(code, is_assignment_expression)
      end
    end

    def single_line_command?(code)
      command = code.split(/\s/, 2).first
      @context.symbol_alias?(command) || @context.transform_args?(command)
    end

    def configure_io
      if @context.io.respond_to?(:check_termination)
        @context.io.check_termination do |code|
          if Reline::IOGate.in_pasting?
            rest = @scanner.check_termination_in_prev_line(code, local_variables: @context.local_variables)
            if rest
              Reline.delete_text
              rest.bytes.reverse_each do |c|
                Reline.ungetc(c)
              end
              true
            else
              false
            end
          else
            # Accept any single-line input for symbol aliases or commands that transform args
            next true if single_line_command?(code)

            _tokens, _opens, terminated = @scanner.check_code_state(code, local_variables: @context.local_variables)
            terminated
          end
        end
      end
      if @context.io.respond_to?(:dynamic_prompt)
        @context.io.dynamic_prompt do |lines|
          lines << '' if lines.empty?
          tokens = RubyLex.ripper_lex_without_warning(lines.map{ |l| l + "\n" }.join, local_variables: @context.local_variables)
          line_results = IRB::NestingParser.parse_by_line(tokens)
          tokens_until_line = []
          line_results.map.with_index do |(line_tokens, _prev_opens, next_opens, _min_depth), line_num_offset|
            line_tokens.each do |token, _s|
              # Avoid appending duplicated token. Tokens that include "\n" like multiline tstring_content can exist in multiple lines.
              tokens_until_line << token if token != tokens_until_line.last
            end
            continue = @scanner.should_continue?(tokens_until_line)
            generate_prompt(next_opens, continue, line_num_offset)
          end
        end
      end

      if @context.io.respond_to?(:auto_indent) and @context.auto_indent_mode
        @context.io.auto_indent do |lines, line_index, byte_pointer, is_newline|
          next nil if lines == [nil] # Workaround for exit IRB with CTRL+d
          next nil if !is_newline && lines[line_index]&.byteslice(0, byte_pointer)&.match?(/\A\s*\z/)

          code = lines[0..line_index].map { |l| "#{l}\n" }.join
          tokens = RubyLex.ripper_lex_without_warning(code, local_variables: @context.local_variables)
          @scanner.process_indent_level(tokens, lines, line_index, is_newline)
        end
      end
    end

    def convert_invalid_byte_sequence(str, enc)
      str.force_encoding(enc)
      str.scrub { |c|
        c.bytes.map{ |b| "\\x#{b.to_s(16).upcase}" }.join
      }
    end

    def encode_with_invalid_byte_sequence(str, enc)
      conv = Encoding::Converter.new(str.encoding, enc)
      dst = String.new
      begin
        ret = conv.primitive_convert(str, dst)
        case ret
        when :invalid_byte_sequence
          conv.insert_output(conv.primitive_errinfo[3].dump[1..-2])
          redo
        when :undefined_conversion
          c = conv.primitive_errinfo[3].dup.force_encoding(conv.primitive_errinfo[1])
          conv.insert_output(c.dump[1..-2])
          redo
        when :incomplete_input
          conv.insert_output(conv.primitive_errinfo[3].dump[1..-2])
        when :finished
        end
        break
      end while nil
      dst
    end

    def handle_exception(exc)
      if exc.backtrace[0] =~ /\/irb(2)?(\/.*|-.*|\.rb)?:/ && exc.class.to_s !~ /^IRB/ &&
         !(SyntaxError === exc) && !(EncodingError === exc)
        # The backtrace of invalid encoding hash (ex. {"\xAE": 1}) raises EncodingError without lineno.
        irb_bug = true
      else
        irb_bug = false
      end

      if RUBY_VERSION < '3.0.0'
        if STDOUT.tty?
          message = exc.full_message(order: :bottom)
          order = :bottom
        else
          message = exc.full_message(order: :top)
          order = :top
        end
      else # '3.0.0' <= RUBY_VERSION
        message = exc.full_message(order: :top)
        order = :top
      end
      message = convert_invalid_byte_sequence(message, exc.message.encoding)
      message = encode_with_invalid_byte_sequence(message, IRB.conf[:LC_MESSAGES].encoding) unless message.encoding.to_s.casecmp?(IRB.conf[:LC_MESSAGES].encoding.to_s)
      message = message.gsub(/((?:^\t.+$\n)+)/) { |m|
        case order
        when :top
          lines = m.split("\n")
        when :bottom
          lines = m.split("\n").reverse
        end
        unless irb_bug
          lines = lines.map { |l| @context.workspace.filter_backtrace(l) }.compact
          if lines.size > @context.back_trace_limit
            omit = lines.size - @context.back_trace_limit
            lines = lines[0..(@context.back_trace_limit - 1)]
            lines << "\t... %d levels..." % omit
          end
        end
        lines = lines.reverse if order == :bottom
        lines.map{ |l| l + "\n" }.join
      }
      # The "<top (required)>" in "(irb)" may be the top level of IRB so imitate the main object.
      message = message.gsub(/\(irb\):(?<num>\d+):in `<(?<frame>top \(required\))>'/) { "(irb):#{$~[:num]}:in `<main>'" }
      puts message
      puts 'Maybe IRB bug!' if irb_bug
    rescue Exception => handler_exc
      begin
        puts exc.inspect
        puts "backtraces are hidden because #{handler_exc} was raised when processing them"
      rescue Exception
        puts 'Uninspectable exception occurred'
      end
    end

    # Evaluates the given block using the given +path+ as the Context#irb_path
    # and +name+ as the Context#irb_name.
    #
    # Used by the irb command +source+, see IRB@IRB+Sessions for more
    # information.
    def suspend_name(path = nil, name = nil)
      @context.irb_path, back_path = path, @context.irb_path if path
      @context.irb_name, back_name = name, @context.irb_name if name
      begin
        yield back_path, back_name
      ensure
        @context.irb_path = back_path if path
        @context.irb_name = back_name if name
      end
    end

    # Evaluates the given block using the given +workspace+ as the
    # Context#workspace.
    #
    # Used by the irb command +irb_load+, see IRB@IRB+Sessions for more
    # information.
    def suspend_workspace(workspace)
      @context.workspace, back_workspace = workspace, @context.workspace
      begin
        yield back_workspace
      ensure
        @context.workspace = back_workspace
      end
    end

    # Evaluates the given block using the given +input_method+ as the
    # Context#io.
    #
    # Used by the irb commands +source+ and +irb_load+, see IRB@IRB+Sessions
    # for more information.
    def suspend_input_method(input_method)
      back_io = @context.io
      @context.instance_eval{@io = input_method}
      begin
        yield back_io
      ensure
        @context.instance_eval{@io = back_io}
      end
    end

    # Handler for the signal SIGINT, see Kernel#trap for more information.
    def signal_handle
      unless @context.ignore_sigint?
        print "\nabort!\n" if @context.verbose?
        exit
      end

      case @signal_status
      when :IN_INPUT
        print "^C\n"
        raise RubyLex::TerminateLineInput
      when :IN_EVAL
        IRB.irb_abort(self)
      when :IN_LOAD
        IRB.irb_abort(self, LoadAbort)
      when :IN_IRB
        # ignore
      else
        # ignore other cases as well
      end
    end

    # Evaluates the given block using the given +status+.
    def signal_status(status)
      return yield if @signal_status == :IN_LOAD

      signal_status_back = @signal_status
      @signal_status = status
      begin
        yield
      ensure
        @signal_status = signal_status_back
      end
    end

    def output_value(omit = false) # :nodoc:
      str = @context.inspect_last_value
      multiline_p = str.include?("\n")
      if omit
        winwidth = @context.io.winsize.last
        if multiline_p
          first_line = str.split("\n").first
          result = @context.newline_before_multiline_output? ? (@context.return_format % first_line) : first_line
          output_width = Reline::Unicode.calculate_width(result, true)
          diff_size = output_width - Reline::Unicode.calculate_width(first_line, true)
          if diff_size.positive? and output_width > winwidth
            lines, _ = Reline::Unicode.split_by_width(first_line, winwidth - diff_size - 3)
            str = "%s..." % lines.first
            str += "\e[0m" if Color.colorable?
            multiline_p = false
          else
            str = str.gsub(/(\A.*?\n).*/m, "\\1...")
            str += "\e[0m" if Color.colorable?
          end
        else
          output_width = Reline::Unicode.calculate_width(@context.return_format % str, true)
          diff_size = output_width - Reline::Unicode.calculate_width(str, true)
          if diff_size.positive? and output_width > winwidth
            lines, _ = Reline::Unicode.split_by_width(str, winwidth - diff_size - 3)
            str = "%s..." % lines.first
            str += "\e[0m" if Color.colorable?
          end
        end
      end

      if multiline_p && @context.newline_before_multiline_output?
        str = "\n" + str
      end

      Pager.page_content(format(@context.return_format, str), retain_content: true)
    end

    # Outputs the local variables to this current session, including
    # #signal_status and #context, using IRB::Locale.
    def inspect
      ary = []
      for iv in instance_variables
        case (iv = iv.to_s)
        when "@signal_status"
          ary.push format("%s=:%s", iv, @signal_status.id2name)
        when "@context"
          ary.push format("%s=%s", iv, eval(iv).__to_s__)
        else
          ary.push format("%s=%s", iv, eval(iv))
        end
      end
      format("#<%s: %s>", self.class, ary.join(", "))
    end

    private

    def generate_prompt(opens, continue, line_offset)
      ltype = @scanner.ltype_from_open_tokens(opens)
      indent = @scanner.calc_indent_level(opens)
      continue = opens.any? || continue
      line_no = @line_no + line_offset

      if ltype
        f = @context.prompt_s
      elsif continue
        f = @context.prompt_c
      else
        f = @context.prompt_i
      end
      f = "" unless f
      if @context.prompting?
        p = format_prompt(f, ltype, indent, line_no)
      else
        p = ""
      end
      if @context.auto_indent_mode and !@context.io.respond_to?(:auto_indent)
        unless ltype
          prompt_i = @context.prompt_i.nil? ? "" : @context.prompt_i
          ind = format_prompt(prompt_i, ltype, indent, line_no)[/.*\z/].size +
            indent * 2 - p.size
          p += " " * ind if ind > 0
        end
      end
      p
    end

    def truncate_prompt_main(str) # :nodoc:
      str = str.tr(CONTROL_CHARACTERS_PATTERN, ' ')
      if str.size <= PROMPT_MAIN_TRUNCATE_LENGTH
        str
      else
        str[0, PROMPT_MAIN_TRUNCATE_LENGTH - PROMPT_MAIN_TRUNCATE_OMISSION.size] + PROMPT_MAIN_TRUNCATE_OMISSION
      end
    end

    def format_prompt(format, ltype, indent, line_no) # :nodoc:
      format.gsub(/%([0-9]+)?([a-zA-Z])/) do
        case $2
        when "N"
          @context.irb_name
        when "m"
          main_str = @context.main.to_s rescue "!#{$!.class}"
          truncate_prompt_main(main_str)
        when "M"
          main_str = @context.main.inspect rescue "!#{$!.class}"
          truncate_prompt_main(main_str)
        when "l"
          ltype
        when "i"
          if indent < 0
            if $1
              "-".rjust($1.to_i)
            else
              "-"
            end
          else
            if $1
              format("%" + $1 + "d", indent)
            else
              indent.to_s
            end
          end
        when "n"
          if $1
            format("%" + $1 + "d", line_no)
          else
            line_no.to_s
          end
        when "%"
          "%"
        end
      end
    end
  end
end

class Binding
  # Opens an IRB session where +binding.irb+ is called which allows for
  # interactive debugging. You can call any methods or variables available in
  # the current scope, and mutate state if you need to.
  #
  #
  # Given a Ruby file called +potato.rb+ containing the following code:
  #
  #     class Potato
  #       def initialize
  #         @cooked = false
  #         binding.irb
  #         puts "Cooked potato: #{@cooked}"
  #       end
  #     end
  #
  #     Potato.new
  #
  # Running <code>ruby potato.rb</code> will open an IRB session where
  # +binding.irb+ is called, and you will see the following:
  #
  #     $ ruby potato.rb
  #
  #     From: potato.rb @ line 4 :
  #
  #         1: class Potato
  #         2:   def initialize
  #         3:     @cooked = false
  #      => 4:     binding.irb
  #         5:     puts "Cooked potato: #{@cooked}"
  #         6:   end
  #         7: end
  #         8:
  #         9: Potato.new
  #
  #     irb(#<Potato:0x00007feea1916670>):001:0>
  #
  # You can type any valid Ruby code and it will be evaluated in the current
  # context. This allows you to debug without having to run your code repeatedly:
  #
  #     irb(#<Potato:0x00007feea1916670>):001:0> @cooked
  #     => false
  #     irb(#<Potato:0x00007feea1916670>):002:0> self.class
  #     => Potato
  #     irb(#<Potato:0x00007feea1916670>):003:0> caller.first
  #     => ".../2.5.1/lib/ruby/2.5.0/irb/workspace.rb:85:in `eval'"
  #     irb(#<Potato:0x00007feea1916670>):004:0> @cooked = true
  #     => true
  #
  # You can exit the IRB session with the +exit+ command. Note that exiting will
  # resume execution where +binding.irb+ had paused it, as you can see from the
  # output printed to standard output in this example:
  #
  #     irb(#<Potato:0x00007feea1916670>):005:0> exit
  #     Cooked potato: true
  #
  #
  # See IRB@Usage for more information.
  def irb(show_code: true)
    # Setup IRB with the current file's path and no command line arguments
    IRB.setup(source_location[0], argv: [])
    # Create a new workspace using the current binding
    workspace = IRB::WorkSpace.new(self)
    # Print the code around the binding if show_code is true
    STDOUT.print(workspace.code_around_binding) if show_code
    # Get the original IRB instance
    debugger_irb = IRB.instance_variable_get(:@debugger_irb)

    irb_path = File.expand_path(source_location[0])

    if debugger_irb
      # If we're already in a debugger session, set the workspace and irb_path for the original IRB instance
      debugger_irb.context.workspace = workspace
      debugger_irb.context.irb_path = irb_path
      # If we've started a debugger session and hit another binding.irb, we don't want to start an IRB session
      # instead, we want to resume the irb:rdbg session.
      IRB::Debug.setup(debugger_irb)
      IRB::Debug.insert_debug_break
      debugger_irb.debug_break
    else
      # If we're not in a debugger session, create a new IRB instance with the current workspace
      binding_irb = IRB::Irb.new(workspace)
      binding_irb.context.irb_path = irb_path
      binding_irb.run(IRB.conf)
      binding_irb.debug_break
    end
  end
end
