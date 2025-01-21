# frozen_string_literal: true

# :markup: markdown
#   irb.rb - irb main module
#       by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require "ripper"
require "reline"

require_relative "irb/init"
require_relative "irb/context"
require_relative "irb/default_commands"

require_relative "irb/ruby-lex"
require_relative "irb/statement"
require_relative "irb/history"
require_relative "irb/input-method"
require_relative "irb/locale"
require_relative "irb/color"

require_relative "irb/version"
require_relative "irb/easter-egg"
require_relative "irb/debug"
require_relative "irb/pager"

module IRB

  # An exception raised by IRB.irb_abort
  class Abort < Exception;end # :nodoc:

  class << self
    # The current IRB::Context of the session, see IRB.conf
    #
    #     irb
    #     irb(main):001:0> IRB.CurrentContext.irb_name = "foo"
    #     foo(main):002:0> IRB.conf[:MAIN_CONTEXT].irb_name #=> "foo"
    def CurrentContext # :nodoc:
      conf[:MAIN_CONTEXT]
    end

    # Initializes IRB and creates a new Irb.irb object at the `TOPLEVEL_BINDING`
    def start(ap_path = nil)
      STDOUT.sync = true
      $0 = File::basename(ap_path, ".rb") if ap_path

      setup(ap_path)

      if @CONF[:SCRIPT]
        irb = Irb.new(nil, @CONF[:SCRIPT])
      else
        irb = Irb.new
      end
      irb.run(@CONF)
    end

    # Quits irb
    def irb_exit(*) # :nodoc:
      throw :IRB_EXIT, false
    end

    # Aborts then interrupts irb.
    #
    # Will raise an Abort exception, or the given `exception`.
    def irb_abort(irb, exception = Abort) # :nodoc:
      irb.context.thread.raise exception, "abort then interrupt!"
    end
  end

  class Irb
    # Note: instance and index assignment expressions could also be written like:
    # "foo.bar=(1)" and "foo.[]=(1, bar)", when expressed that way, the former be
    # parsed as :assign and echo will be suppressed, but the latter is parsed as a
    # :method_add_arg and the output won't be suppressed

    PROMPT_MAIN_TRUNCATE_LENGTH = 32
    PROMPT_MAIN_TRUNCATE_OMISSION = '...'
    CONTROL_CHARACTERS_PATTERN = "\x00-\x1F"

    # Returns the current context of this irb session
    attr_reader :context
    # The lexer used by this irb session
    attr_accessor :scanner

    attr_reader :from_binding

    # Creates a new irb session
    def initialize(workspace = nil, input_method = nil, from_binding: false)
      @from_binding = from_binding
      @context = Context.new(self, workspace, input_method)
      @context.workspace.load_helper_methods_to_main
      @signal_status = :IN_IRB
      @scanner = RubyLex.new
      @line_no = 1
    end

    # A hook point for `debug` command's breakpoint after :IRB_EXIT as well as its
    # clean-up
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
      context.replace_workspace(workspace)
      context.workspace.load_helper_methods_to_main
      @line_no += 1

      # When users run:
      # 1.  Debugging commands, like `step 2`
      # 2.  Any input that's not irb-command, like `foo = 123`
      #
      #
      # Irb#eval_input will simply return the input, and we need to pass it to the
      # debugger.
      input = nil
      forced_exit = catch(:IRB_EXIT) do
        if History.save_history? && context.io.support_history_saving?
          # Previous IRB session's history has been saved when `Irb#run` is exited We need
          # to make sure the saved history is not saved again by resetting the counter
          context.io.reset_history_counter

          begin
            input = eval_input
          ensure
            context.io.save_history
          end
        else
          input = eval_input
        end
        false
      end

      Kernel.exit if forced_exit

      if input&.include?("\n")
        @line_no += input.count("\n") - 1
      end

      input
    end

    def run(conf = IRB.conf)
      in_nested_session = !!conf[:MAIN_CONTEXT]
      conf[:IRB_RC].call(context) if conf[:IRB_RC]
      prev_context = conf[:MAIN_CONTEXT]
      conf[:MAIN_CONTEXT] = context

      load_history = !in_nested_session && context.io.support_history_saving?
      save_history = load_history && History.save_history?

      if load_history
        context.io.load_history
      end

      prev_trap = trap("SIGINT") do
        signal_handle
      end

      begin
        if defined?(RubyVM.keep_script_lines)
          keep_script_lines_backup = RubyVM.keep_script_lines
          RubyVM.keep_script_lines = true
        end

        forced_exit = catch(:IRB_EXIT) do
          eval_input
        end
      ensure
        # Do not restore to nil. It will cause IRB crash when used with threads.
        IRB.conf[:MAIN_CONTEXT] = prev_context if prev_context

        RubyVM.keep_script_lines = keep_script_lines_backup if defined?(RubyVM.keep_script_lines)
        trap("SIGINT", prev_trap)
        conf[:AT_EXIT].each{|hook| hook.call}

        context.io.save_history if save_history
        Kernel.exit if forced_exit
      end
    end

    # Evaluates input for this session.
    def eval_input
      configure_io

      each_top_level_statement do |statement, line_no|
        signal_status(:IN_EVAL) do
          begin
            # If the integration with debugger is activated, we return certain input if it
            # should be dealt with by debugger
            if @context.with_debugger && statement.should_be_handled_by_debugger?
              return statement.code
            end

            @context.evaluate(statement, line_no)

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
      code = +''
      line_offset = 0
      loop do
        line = read_input(prompt)
        unless line
          return code.empty? ? nil : code
        end

        code << line
        return code if command?(code)

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
        yield parse_input(code), @line_no
        @line_no += code.count("\n")
      rescue RubyLex::TerminateLineInput
      end
    end

    def parse_input(code)
      if code.match?(/\A\n*\z/)
        return Statement::EmptyInput.new
      end

      code = code.dup.force_encoding(@context.io.encoding)
      is_assignment_expression = @scanner.assignment_expression?(code, local_variables: @context.local_variables)

      @context.parse_input(code, is_assignment_expression)
    end

    def command?(code)
      parse_input(code).is_a?(Statement::Command)
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
            next true if command?(code)

            _tokens, _opens, terminated = @scanner.check_code_state(code, local_variables: @context.local_variables)
            terminated
          end
        end
      end
      if @context.io.respond_to?(:dynamic_prompt)
        @context.io.dynamic_prompt do |lines|
          tokens = RubyLex.ripper_lex_without_warning(lines.map{ |l| l + "\n" }.join, local_variables: @context.local_variables)
          line_results = IRB::NestingParser.parse_by_line(tokens)
          tokens_until_line = []
          line_results.map.with_index do |(line_tokens, _prev_opens, next_opens, _min_depth), line_num_offset|
            line_tokens.each do |token, _s|
              # Avoid appending duplicated token. Tokens that include "n" like multiline
              # tstring_content can exist in multiple lines.
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
        # To support backtrace filtering while utilizing Exception#full_message, we need to clone
        # the exception to avoid modifying the original exception's backtrace.
        exc = exc.clone
        filtered_backtrace = exc.backtrace.map { |l| @context.workspace.filter_backtrace(l) }.compact
        backtrace_filter = IRB.conf[:BACKTRACE_FILTER]

        if backtrace_filter
          if backtrace_filter.respond_to?(:call)
            filtered_backtrace = backtrace_filter.call(filtered_backtrace)
          else
            warn "IRB.conf[:BACKTRACE_FILTER] #{backtrace_filter} should respond to `call` method"
          end
        end

        exc.set_backtrace(filtered_backtrace)
      end

      highlight = Color.colorable?

      order =
        if RUBY_VERSION < '3.0.0'
          STDOUT.tty? ? :bottom : :top
        else # '3.0.0' <= RUBY_VERSION
          :top
        end

      message = exc.full_message(order: order, highlight: highlight)
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
      message = message.gsub(/\(irb\):(?<num>\d+):in (?<open_quote>[`'])<(?<frame>top \(required\))>'/) { "(irb):#{$~[:num]}:in #{$~[:open_quote]}<main>'" }
      puts message

      if irb_bug
        puts "This may be an issue with IRB. If you believe this is an unexpected behavior, please report it to https://github.com/ruby/irb/issues"
      end
    rescue Exception => handler_exc
      begin
        puts exc.inspect
        puts "backtraces are hidden because #{handler_exc} was raised when processing them"
      rescue Exception
        puts 'Uninspectable exception occurred'
      end
    end

    # Evaluates the given block using the given `path` as the Context#irb_path and
    # `name` as the Context#irb_name.
    #
    # Used by the irb command `source`, see IRB@IRB+Sessions for more information.
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

    # Evaluates the given block using the given `workspace` as the
    # Context#workspace.
    #
    # Used by the irb command `irb_load`, see IRB@IRB+Sessions for more information.
    def suspend_workspace(workspace)
      current_workspace = @context.workspace
      @context.replace_workspace(workspace)
      yield
    ensure
      @context.replace_workspace current_workspace
    end

    # Evaluates the given block using the given `input_method` as the Context#io.
    #
    # Used by the irb commands `source` and `irb_load`, see IRB@IRB+Sessions for
    # more information.
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

    # Evaluates the given block using the given `status`.
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
      unless @context.return_format.include?('%')
        puts @context.return_format
        return
      end

      winheight, winwidth = @context.io.winsize
      if omit
        content, overflow = Pager.take_first_page(winwidth, 1) do |out|
          @context.inspect_last_value(out)
        end
        if overflow
          content = "\n#{content}" if @context.newline_before_multiline_output?
          content = "#{content}..."
          content = "#{content}\e[0m" if Color.colorable?
        end
        puts format(@context.return_format, content.chomp)
      elsif Pager.should_page? && @context.inspector_support_stream_output?
        formatter_proc = ->(content, multipage) do
          content = content.chomp
          content = "\n#{content}" if @context.newline_before_multiline_output? && (multipage || content.include?("\n"))
          format(@context.return_format, content)
        end
        Pager.page_with_preview(winwidth, winheight, formatter_proc) do |out|
          @context.inspect_last_value(out)
        end
      else
        content = @context.inspect_last_value.chomp
        content = "\n#{content}" if @context.newline_before_multiline_output? && content.include?("\n")
        Pager.page_content(format(@context.return_format, content), retain_content: true)
      end
    end

    # Outputs the local variables to this current session, including #signal_status
    # and #context, using IRB::Locale.
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
      format.gsub(/%([0-9]+)?([a-zA-Z%])/) do
        case $2
        when "N"
          @context.irb_name
        when "m"
          main_str = @context.safe_method_call_on_main(:to_s) rescue "!#{$!.class}"
          truncate_prompt_main(main_str)
        when "M"
          main_str = @context.safe_method_call_on_main(:inspect) rescue "!#{$!.class}"
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
          "%" unless $1
        end
      end
    end
  end
end

class Binding
  # Opens an IRB session where `binding.irb` is called which allows for
  # interactive debugging. You can call any methods or variables available in the
  # current scope, and mutate state if you need to.
  #
  # Given a Ruby file called `potato.rb` containing the following code:
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
  # Running `ruby potato.rb` will open an IRB session where `binding.irb` is
  # called, and you will see the following:
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
  # You can exit the IRB session with the `exit` command. Note that exiting will
  # resume execution where `binding.irb` had paused it, as you can see from the
  # output printed to standard output in this example:
  #
  #     irb(#<Potato:0x00007feea1916670>):005:0> exit
  #     Cooked potato: true
  #
  # See IRB for more information.
  def irb(show_code: true)
    # Setup IRB with the current file's path and no command line arguments
    IRB.setup(source_location[0], argv: []) unless IRB.initialized?
    # Create a new workspace using the current binding
    workspace = IRB::WorkSpace.new(self)
    # Print the code around the binding if show_code is true
    STDOUT.print(workspace.code_around_binding) if show_code
    # Get the original IRB instance
    debugger_irb = IRB.instance_variable_get(:@debugger_irb)

    irb_path = File.expand_path(source_location[0])

    if debugger_irb
      # If we're already in a debugger session, set the workspace and irb_path for the original IRB instance
      debugger_irb.context.replace_workspace(workspace)
      debugger_irb.context.irb_path = irb_path
      # If we've started a debugger session and hit another binding.irb, we don't want
      # to start an IRB session instead, we want to resume the irb:rdbg session.
      IRB::Debug.setup(debugger_irb)
      IRB::Debug.insert_debug_break
      debugger_irb.debug_break
    else
      # If we're not in a debugger session, create a new IRB instance with the current
      # workspace
      binding_irb = IRB::Irb.new(workspace, from_binding: true)
      binding_irb.context.irb_path = irb_path
      binding_irb.run(IRB.conf)
      binding_irb.debug_break
    end
  end
end
