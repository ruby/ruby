# frozen_string_literal: false
#
#   irb/context.rb - irb context
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
require "irb/workspace"
require "irb/inspector"

module IRB
  # A class that wraps the current state of the irb session, including the
  # configuration of IRB.conf.
  class Context
    # Creates a new IRB context.
    #
    # The optional +input_method+ argument:
    #
    # +nil+::     uses stdin or Readline
    # +String+::  uses a File
    # +other+::   uses this as InputMethod
    def initialize(irb, workspace = nil, input_method = nil, output_method = nil)
      @irb = irb
      if workspace
        @workspace = workspace
      else
        @workspace = WorkSpace.new
      end
      @thread = Thread.current if defined? Thread

      # copy of default configuration
      @ap_name = IRB.conf[:AP_NAME]
      @rc = IRB.conf[:RC]
      @load_modules = IRB.conf[:LOAD_MODULES]

      @use_readline = IRB.conf[:USE_READLINE]
      @verbose = IRB.conf[:VERBOSE]
      @io = nil

      self.inspect_mode = IRB.conf[:INSPECT_MODE]
      self.math_mode = IRB.conf[:MATH_MODE] if IRB.conf[:MATH_MODE]
      self.use_tracer = IRB.conf[:USE_TRACER] if IRB.conf[:USE_TRACER]
      self.use_loader = IRB.conf[:USE_LOADER] if IRB.conf[:USE_LOADER]
      self.eval_history = IRB.conf[:EVAL_HISTORY] if IRB.conf[:EVAL_HISTORY]

      @ignore_sigint = IRB.conf[:IGNORE_SIGINT]
      @ignore_eof = IRB.conf[:IGNORE_EOF]

      @back_trace_limit = IRB.conf[:BACK_TRACE_LIMIT]

      self.prompt_mode = IRB.conf[:PROMPT_MODE]

      if IRB.conf[:SINGLE_IRB] or !defined?(IRB::JobManager)
        @irb_name = IRB.conf[:IRB_NAME]
      else
        @irb_name = IRB.conf[:IRB_NAME]+"#"+IRB.JobManager.n_jobs.to_s
      end
      @irb_path = "(" + @irb_name + ")"

      case input_method
      when nil
        case use_readline?
        when nil
          if (defined?(ReadlineInputMethod) && STDIN.tty? &&
              IRB.conf[:PROMPT_MODE] != :INF_RUBY)
            @io = ReadlineInputMethod.new
          else
            @io = StdioInputMethod.new
          end
        when false
          @io = StdioInputMethod.new
        when true
          if defined?(ReadlineInputMethod)
            @io = ReadlineInputMethod.new
          else
            @io = StdioInputMethod.new
          end
        end

      when String
        @io = FileInputMethod.new(input_method)
        @irb_name = File.basename(input_method)
        @irb_path = input_method
      else
        @io = input_method
      end
      self.save_history = IRB.conf[:SAVE_HISTORY] if IRB.conf[:SAVE_HISTORY]

      if output_method
        @output_method = output_method
      else
        @output_method = StdioOutputMethod.new
      end

      @echo = IRB.conf[:ECHO]
      if @echo.nil?
        @echo = true
      end
      self.debug_level = IRB.conf[:DEBUG_LEVEL]
    end

    # The top-level workspace, see WorkSpace#main
    def main
      @workspace.main
    end

    # The toplevel workspace, see #home_workspace
    attr_reader :workspace_home
    # WorkSpace in the current context
    attr_accessor :workspace
    # The current thread in this context
    attr_reader :thread
    # The current input method
    #
    # Can be either StdioInputMethod, ReadlineInputMethod, FileInputMethod or
    # other specified when the context is created. See ::new for more
    # information on +input_method+.
    attr_accessor :io

    # Current irb session
    attr_accessor :irb
    # A copy of the default <code>IRB.conf[:AP_NAME]</code>
    attr_accessor :ap_name
    # A copy of the default <code>IRB.conf[:RC]</code>
    attr_accessor :rc
    # A copy of the default <code>IRB.conf[:LOAD_MODULES]</code>
    attr_accessor :load_modules
    # Can be either name from <code>IRB.conf[:IRB_NAME]</code>, or the number of
    # the current job set by JobManager, such as <code>irb#2</code>
    attr_accessor :irb_name
    # Can be either the #irb_name surrounded by parenthesis, or the
    # +input_method+ passed to Context.new
    attr_accessor :irb_path

    # Whether +Readline+ is enabled or not.
    #
    # A copy of the default <code>IRB.conf[:USE_READLINE]</code>
    #
    # See #use_readline= for more information.
    attr_reader :use_readline
    # A copy of the default <code>IRB.conf[:INSPECT_MODE]</code>
    attr_reader :inspect_mode

    # A copy of the default <code>IRB.conf[:PROMPT_MODE]</code>
    attr_reader :prompt_mode
    # Standard IRB prompt
    #
    # See IRB@Customizing+the+IRB+Prompt for more information.
    attr_accessor :prompt_i
    # IRB prompt for continuated strings
    #
    # See IRB@Customizing+the+IRB+Prompt for more information.
    attr_accessor :prompt_s
    # IRB prompt for continuated statement (e.g. immediately after an +if+)
    #
    # See IRB@Customizing+the+IRB+Prompt for more information.
    attr_accessor :prompt_c
    # See IRB@Customizing+the+IRB+Prompt for more information.
    attr_accessor :prompt_n
    # Can be either the default <code>IRB.conf[:AUTO_INDENT]</code>, or the
    # mode set by #prompt_mode=
    #
    # To enable auto-indentation in irb:
    #
    #     IRB.conf[:AUTO_INDENT] = true
    #
    # or
    #
    #     irb_context.auto_indent_mode = true
    #
    # or
    #
    #     IRB.CurrentContext.auto_indent_mode = true
    #
    # See IRB@Configuration for more information.
    attr_accessor :auto_indent_mode
    # The format of the return statement, set by #prompt_mode= using the
    # +:RETURN+ of the +mode+ passed to set the current #prompt_mode.
    attr_accessor :return_format

    # Whether <code>^C</code> (+control-c+) will be ignored or not.
    #
    # If set to +false+, <code>^C</code> will quit irb.
    #
    # If set to +true+,
    #
    # * during input:   cancel input then return to top level.
    # * during execute: abandon current execution.
    attr_accessor :ignore_sigint
    # Whether <code>^D</code> (+control-d+) will be ignored or not.
    #
    # If set to +false+, <code>^D</code> will quit irb.
    attr_accessor :ignore_eof
    # Whether to echo the return value to output or not.
    #
    # Uses IRB.conf[:ECHO] if available, or defaults to +true+.
    #
    #     puts "hello"
    #     # hello
    #     #=> nil
    #     IRB.CurrentContext.echo = false
    #     puts "omg"
    #     # omg
    attr_accessor :echo
    # Whether verbose messages are displayed or not.
    #
    # A copy of the default <code>IRB.conf[:VERBOSE]</code>
    attr_accessor :verbose
    # The debug level of irb
    #
    # See #debug_level= for more information.
    attr_reader :debug_level

    # The limit of backtrace lines displayed as top +n+ and tail +n+.
    #
    # The default value is 16.
    #
    # Can also be set using the +--back-trace-limit+ command line option.
    #
    # See IRB@Command+line+options for more command line options.
    attr_accessor :back_trace_limit

    # Alias for #use_readline
    alias use_readline? use_readline
    # Alias for #rc
    alias rc? rc
    alias ignore_sigint? ignore_sigint
    alias ignore_eof? ignore_eof
    alias echo? echo

    # Returns whether messages are displayed or not.
    def verbose?
      if @verbose.nil?
        if defined?(ReadlineInputMethod) && @io.kind_of?(ReadlineInputMethod)
          false
        elsif !STDIN.tty? or @io.kind_of?(FileInputMethod)
          true
        else
          false
        end
      else
        @verbose
      end
    end

    # Whether #verbose? is +true+, and +input_method+ is either
    # StdioInputMethod or ReadlineInputMethod, see #io for more information.
    def prompting?
      verbose? || (STDIN.tty? && @io.kind_of?(StdioInputMethod) ||
                   (defined?(ReadlineInputMethod) && @io.kind_of?(ReadlineInputMethod)))
    end

    # The return value of the last statement evaluated.
    attr_reader :last_value

    # Sets the return value from the last statement evaluated in this context
    # to #last_value.
    def set_last_value(value)
      @last_value = value
      @workspace.evaluate self, "_ = IRB.CurrentContext.last_value"
    end

    # Sets the +mode+ of the prompt in this context.
    #
    # See IRB@Customizing+the+IRB+Prompt for more information.
    def prompt_mode=(mode)
      @prompt_mode = mode
      pconf = IRB.conf[:PROMPT][mode]
      @prompt_i = pconf[:PROMPT_I]
      @prompt_s = pconf[:PROMPT_S]
      @prompt_c = pconf[:PROMPT_C]
      @prompt_n = pconf[:PROMPT_N]
      @return_format = pconf[:RETURN]
      if ai = pconf.include?(:AUTO_INDENT)
        @auto_indent_mode = ai
      else
        @auto_indent_mode = IRB.conf[:AUTO_INDENT]
      end
    end

    # Whether #inspect_mode is set or not, see #inspect_mode= for more detail.
    def inspect?
      @inspect_mode.nil? or @inspect_mode
    end

    # Whether #io uses a File for the +input_method+ passed when creating the
    # current context, see ::new
    def file_input?
      @io.class == FileInputMethod
    end

    # Specifies the inspect mode with +opt+:
    #
    # +true+::  display +inspect+
    # +false+:: display +to_s+
    # +nil+::   inspect mode in non-math mode,
    #           non-inspect mode in math mode
    #
    # See IRB::Inspector for more information.
    #
    # Can also be set using the +--inspect+ and +--noinspect+ command line
    # options.
    #
    # See IRB@Command+line+options for more command line options.
    def inspect_mode=(opt)

      if i = Inspector::INSPECTORS[opt]
        @inspect_mode = opt
        @inspect_method = i
        i.init
      else
        case opt
        when nil
          if Inspector.keys_with_inspector(Inspector::INSPECTORS[true]).include?(@inspect_mode)
            self.inspect_mode = false
          elsif Inspector.keys_with_inspector(Inspector::INSPECTORS[false]).include?(@inspect_mode)
            self.inspect_mode = true
          else
            puts "Can't switch inspect mode."
            return
          end
        when /^\s*\{.*\}\s*$/
          begin
            inspector = eval "proc#{opt}"
          rescue Exception
            puts "Can't switch inspect mode(#{opt})."
            return
          end
          self.inspect_mode = inspector
        when Proc
          self.inspect_mode = IRB::Inspector(opt)
        when Inspector
          prefix = "usr%d"
          i = 1
          while Inspector::INSPECTORS[format(prefix, i)]; i += 1; end
          @inspect_mode = format(prefix, i)
          @inspect_method = opt
          Inspector.def_inspector(format(prefix, i), @inspect_method)
        else
          puts "Can't switch inspect mode(#{opt})."
          return
        end
      end
      print "Switch to#{unless @inspect_mode; ' non';end} inspect mode.\n" if verbose?
      @inspect_mode
    end

    # Obsolete method.
    #
    # Can be set using the +--noreadline+ and +--readline+ command line
    # options.
    #
    # See IRB@Command+line+options for more command line options.
    def use_readline=(opt)
      print "This method is obsolete."
      print "Do nothing."
    end

    # Sets the debug level of irb
    #
    # Can also be set using the +--irb_debug+ command line option.
    #
    # See IRB@Command+line+options for more command line options.
    def debug_level=(value)
      @debug_level = value
      RubyLex.debug_level = value
    end

    # Whether or not debug mode is enabled, see #debug_level=.
    def debug?
      @debug_level > 0
    end

    def evaluate(line, line_no) # :nodoc:
      @line_no = line_no
      set_last_value(@workspace.evaluate(self, line, irb_path, line_no))
    end

    def inspect_last_value # :nodoc:
      @inspect_method.inspect_value(@last_value)
    end

    alias __exit__ exit
    # Exits the current session, see IRB.irb_exit
    def exit(ret = 0)
      IRB.irb_exit(@irb, ret)
    end

    NOPRINTING_IVARS = ["@last_value"] # :nodoc:
    NO_INSPECTING_IVARS = ["@irb", "@io"] # :nodoc:
    IDNAME_IVARS = ["@prompt_mode"] # :nodoc:

    alias __inspect__ inspect
    def inspect # :nodoc:
      array = []
      for ivar in instance_variables.sort{|e1, e2| e1 <=> e2}
        ivar = ivar.to_s
        name = ivar.sub(/^@(.*)$/, '\1')
        val = instance_eval(ivar)
        case ivar
        when *NOPRINTING_IVARS
          array.push format("conf.%s=%s", name, "...")
        when *NO_INSPECTING_IVARS
          array.push format("conf.%s=%s", name, val.to_s)
        when *IDNAME_IVARS
          array.push format("conf.%s=:%s", name, val.id2name)
        else
          array.push format("conf.%s=%s", name, val.inspect)
        end
      end
      array.join("\n")
    end
    alias __to_s__ to_s
    alias to_s inspect
  end
end
