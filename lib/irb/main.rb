#
#   main.rb - irb main module
#   	$Release Version: 0.6 $
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(Nippon Rational Inc.)
#
# --
#
#
#
require "e2mmap"
require "irb/ruby-lex"
require "irb/input-method"
require "irb/workspace-binding"

STDOUT.sync = true

module IRB
  @RCS_ID='-$Id$-'

  # exceptions
  extend Exception2MessageMapper
  def_exception :UnrecognizedSwitch, "Unrecognized switch: %s"
  def_exception :NotImplementError, "Need to define `%s'"
  def_exception :CantRetuenNormalMode, "Can't return normal mode."
  def_exception :IllegalParameter, "Illegal parameter(%s)."
  def_exception :IrbAlreadyDead, "Irb is already dead."
  def_exception :IrbSwitchToCurrentThread, "Change to current thread."
  def_exception :NoSuchJob, "No such job(%s)."
  def_exception :CanNotGoMultiIrbMode, "Can't go multi irb mode."
  def_exception :CanNotChangeBinding, "Can't change binding to (%s)."
  def_exception :UndefinedPromptMode, "Undefined prompt mode(%s)."

  class Abort < Exception;end

  # initialize IRB and start TOP_LEVEL irb
  def IRB.start(ap_path = nil)
    $0 = File::basename(ap_path, ".rb") if ap_path

    IRB.initialize(ap_path)
    IRB.parse_opts
    IRB.load_modules

    bind = workspace_binding
    main = eval("self", bind)

    if @CONF[:SCRIPT]
      irb = Irb.new(main, bind, @CONF[:SCRIPT])
    else
      irb = Irb.new(main, bind)
    end

    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context

    trap("SIGINT") do
      irb.signal_handle
    end
    
    catch(:IRB_EXIT) do
      irb.eval_input
    end
    print "\n"
  end

  # initialize config
  def IRB.initialize(ap_path)
    IRB.init_config(ap_path)
    IRB.run_config
  end

  #
  # @CONF functions
  #
  @CONF = {}
  # @CONF default setting
  def IRB.init_config(ap_path)
    # class instance variables
    @TRACER_INITIALIZED = false
    @MATHN_INITIALIZED = false

    # default configurations
    unless ap_path and @CONF[:AP_NAME]
      ap_path = File.join(File.dirname(File.dirname(__FILE__)), "irb.rb")
    end
    @CONF[:AP_NAME] = File::basename(ap_path, ".rb")

    @CONF[:IRB_NAME] = "irb"
    @CONF[:IRB_LIB_PATH] = File.dirname(__FILE__)

    @CONF[:RC] = true
    @CONF[:LOAD_MODULES] = []
    @CONF[:IRB_RC] = nil

    @CONF[:MATH_MODE] = false
    @CONF[:USE_READLINE] = false unless defined?(ReadlineInputMethod)
    @CONF[:INSPECT_MODE] = nil
    @CONF[:USE_TRACER] = false
    @CONF[:USE_LOADER] = false
    @CONF[:IGNORE_SIGINT] = true
    @CONF[:IGNORE_EOF] = false

    @CONF[:BACK_TRACE_LIMIT] = 16

    @CONF[:PROMPT] = {
      :NULL => {
	:PROMPT_I => nil,
	:PROMPT_S => nil,
	:PROMPT_C => nil,
	:RETURN => "%s\n"
      },
      :DEFAULT => {
	:PROMPT_I => "%N(%m):%03n:%i> ",
	:PROMPT_S => "%N(%m):%03n:%i%l ",
	:PROMPT_C => "%N(%m):%03n:%i* ",
	:RETURN => "%s\n"
      },
      :SIMPLE => {
	:PROMPT_I => ">> ",
	:PROMPT_S => nil,
	:PROMPT_C => "?> ",
	:RETURN => "=> %s\n"
      },
      :INF_RUBY => {
	:PROMPT_I => "%N(%m):%03n:%i> ",
	:PROMPT_S => nil,
	:PROMPT_C => nil,
	:RETURN => "%s\n",
	:AUTO_INDENT => true
      },
      :XMP => {
	:PROMPT_I => nil,
	:PROMPT_S => nil,
	:PROMPT_C => nil,
	:RETURN => "    ==>%s\n"
      }
    }

    @CONF[:PROMPT_MODE] = :DEFAULT
    @CONF[:AUTO_INDENT] = false

    @CONF[:CONTEXT_MODE] = 3
    @CONF[:SINGLE_IRB] = false
    
    @CONF[:DEBUG_LEVEL] = 1
    @CONF[:VERBOSE] = true
  end

  # IRB version method
  def IRB.version
    if v = @CONF[:VERSION] then return v end

    require "irb/version"
    rv = @RELEASE_VERSION.sub(/\.0/, "")
    @CONF[:VERSION] = format("irb %s(%s)", rv, @LAST_UPDATE_DATE)
  end

  def IRB.conf
    @CONF
  end

  # option analyzing
  def IRB.parse_opts
    while opt = ARGV.shift
      case opt
      when "-f"
	opt = ARGV.shift
	@CONF[:RC] = false
      when "-m"
	@CONF[:MATH_MODE] = true
      when "-d"
	$DEBUG = true
      when "-r"
	opt = ARGV.shift
	@CONF[:LOAD_MODULES].push opt if opt
      when "--inspect"
	@CONF[:INSPECT_MODE] = true
      when "--noinspect"
	@CONF[:INSPECT_MODE] = false
      when "--readline"
	@CONF[:USE_READLINE] = true
      when "--noreadline"
	@CONF[:USE_READLINE] = false
      when "--prompt-mode", "--prompt"
	prompt_mode = ARGV.shift.upcase.tr("-", "_").intern
	IRB.fail(UndefinedPromptMode,
		 prompt_mode.id2name) unless @CONF[:PROMPT][prompt_mode]
	@CONF[:PROMPT_MODE] = prompt_mode
      when "--noprompt"
	@CONF[:PROMPT_MODE] = :NULL
      when "--inf-ruby-mode"
	@CONF[:PROMPT_MODE] = :INF_RUBY
      when "--sample-book-mode", "--simple-prompt"
	@CONF[:PROMPT_MODE] = :SIMPLE
      when "--tracer"
	@CONF[:USE_TRACER] = true
      when "--back-trace-limit"
	@CONF[:BACK_TRACE_LIMIT] = ARGV.shift.to_i
      when "--context-mode"
	@CONF[:CONTEXT_MODE] = ARGV.shift.to_i
      when "--single-irb"
	@CONF[:SINGLE_IRB] = true
      when "--irb_debug"
	@CONF[:DEBUG_LEVEL] = ARGV.shift.to_i
      when "-v", "--version"
	print IRB.version, "\n"
	exit(0)
      when /^-/
	IRB.fail UnrecognizedSwitch, opt
      else
	@CONF[:USE_READLINE] = false
	@CONF[:SCRIPT] = opt
	$0 = opt
	break
      end
    end
  end

  # running config
  def IRB.run_config
    if @CONF[:RC]
      rcs = []
      rcs.push File.expand_path("~/.irbrc") if ENV.key?("HOME")
      rcs.push ".irbrc"
      rcs.push "irb.rc"
      rcs.push "_irbrc"
      rcs.push "$irbrc"
      catch(:EXIT) do
	for rc in rcs
	  begin
	    load rc
	    throw :EXIT
	  rescue LoadError, Errno::ENOENT
	  rescue
	    print "load error: #{rc}\n"
	    print $!.type, ": ", $!, "\n"
	    for err in $@[0, $@.size - 2]
	      print "\t", err, "\n"
	    end
	    throw :EXIT
	  end
	end
      end
    end
  end

  # loading modules
  def IRB.load_modules
    for m in @CONF[:LOAD_MODULES]
      begin
	require m
      rescue
	print $@[0], ":", $!.type, ": ", $!, "\n"
      end
    end
  end

  # initialize tracing function
  def IRB.initialize_tracer
    unless @TRACER_INITIALIZED
      require("tracer")
      Tracer.verbose = false
      Tracer.add_filter {
	|event, file, line, id, binding|
	File::dirname(file) != @CONF[:IRB_LIB_PATH]
      }
      @TRACER_INITIALIZED = true
    end
  end

  # initialize mathn function
  def IRB.initialize_mathn
    unless @MATHN_INITIALIZED
      require "mathn"
    @MATHN_INITIALIZED = true
    end
  end

  # initialize loader function
  def IRB.initialize_loader
    unless @LOADER_INITIALIZED
      require "irb/loader"
      @LOADER_INITIALIZED = true
    end
  end

  def IRB.irb_exit(irb, ret)
    throw :IRB_EXIT, ret
  end

  def IRB.irb_abort(irb, exception = Abort)
    if defined? Thread
      irb.context.thread.raise exception, "abort then interrupt!!"
    else
      raise exception, "abort then interrupt!!"
    end
  end

  #
  # irb interpriter main routine 
  #
  class Irb
    def initialize(main, bind, input_method = nil)
      @context = Context.new(self, main, bind, input_method)
      main.extend ExtendCommand
      @signal_status = :IN_IRB

      @scanner = RubyLex.new
      @scanner.exception_on_syntax_error = false
    end
    attr :context
    attr :scanner, true

    def eval_input
#      @scanner = RubyLex.new
      @scanner.set_input(@context.io) do
	signal_status(:IN_INPUT) do
	  unless l = @context.io.gets
	    if @context.ignore_eof? and @context.io.readable_atfer_eof?
	      l = "\n"
	      if @context.verbose?
		printf "Use \"exit\" to leave %s\n", @context.ap_name
	      end
	    end
	  end
	  l
	end
      end

      @scanner.set_prompt do
	|ltype, indent, continue, line_no|
	if ltype
	  f = @context.prompt_s
	elsif continue
	  f = @context.prompt_c
	else @context.prompt_i
	  f = @context.prompt_i
	end
	f = "" unless f
	@context.io.prompt = p = prompt(f, ltype, indent, line_no)
	if @context.auto_indent_mode
	  unless ltype
	    ind = prompt(@context.prompt_i, ltype, indent, line_no).size + 
	      indent * 2 - p.size
	    ind += 2 if continue
	    @context.io.prompt = p + " " * ind if ind > 0
	  end
	end
      end
       
      @scanner.each_top_level_statement do
	|line, line_no|
	signal_status(:IN_EVAL) do
	  begin
	    trace_in do
	      @context._ = eval(line, @context.bind, @context.irb_path, line_no)
#	      @context._ = irb_eval(line, @context.bind, @context.irb_path, line_no)
	    end

	    if @context.inspect?
	      printf @context.return_format, @context._.inspect
	    else
	      printf @context.return_format, @context._
	    end
	  rescue StandardError, ScriptError, Abort
	    $! = RuntimeError.new("unknown exception raised") unless $!
	    print $!.type, ": ", $!, "\n"
	    if  $@[0] =~ /irb(2)?(\/.*|-.*|\.rb)?:/ && $!.type.to_s !~ /^IRB/
	      irb_bug = true 
	    else
	      irb_bug = false
	    end

	    messages = []
	    lasts = []
	    levels = 0
	    for m in $@
	      if m !~ /irb2?(\/.*|-.*|\.rb)?:/ or irb_bug
		if messages.size < @context.back_trace_limit
		  messages.push m
		else
		  lasts.push m
		  if lasts.size > @context.back_trace_limit
		    lasts.shift 
		    levels += 1
		  end
		end
	      end
	    end
	    print messages.join("\n"), "\n"
	    unless lasts.empty?
	      printf "... %d levels...\n", levels if levels > 0
	      print lasts.join("\n")
	    end
	    print "Maybe IRB bug!!\n" if irb_bug
	  end
	end
      end
    end

#     def irb_eval(line, bind, path, line_no)
#       id, str = catch(:IRB_TOPLEVEL_EVAL){
# 	return eval(line, bind, path, line_no)
#       }
#       case id
#       when :EVAL_TOPLEVEL
# 	eval(str, bind, "(irb_internal)", 1)
#       when :EVAL_CONTEXT
# 	@context.instance_eval(str)
#       else
# 	IRB.fail IllegalParameter
#       end
#     end

    def signal_handle
      unless @context.ignore_sigint?
	print "\nabort!!\n" if @context.verbose?
	exit
      end

      case @signal_status
      when :IN_INPUT
	print "^C\n"
	@scanner.initialize_input
	print @context.io.prompt
      when :IN_EVAL
	IRB.irb_abort(self)
      when :IN_LOAD
	IRB.irb_abort(self, LoadAbort)
      when :IN_IRB
	# ignore
      else
	# ignore
      end
    end

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

    def trace_in
      Tracer.on if @context.use_tracer?
      begin
	yield
      ensure
	Tracer.off if @context.use_tracer?
      end
    end

    def prompt(prompt, ltype, indent, line_no)
      p = prompt.dup
      p.gsub!(/%([0-9]+)?([a-zA-Z])/) do
	case $2
	when "N"
	  @context.irb_name
	when "m"
	  @context.main.to_s
	when "M"
	  @context.main.inspect
	when "l"
	  ltype
	when "i"
	  if $1 
	    format("%" + $1 + "d", indent)
	  else
	    indent.to_s
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
      p
    end

    def inspect
      ary = []
      for iv in instance_variables
	case iv
	when "@signal_status"
	  ary.push format("%s=:%s", iv, @signal_status.id2name)
	when "@context"
	  ary.push format("%s=%s", iv, eval(iv).__to_s__)
	else
	  ary.push format("%s=%s", iv, eval(iv))
	end
      end
      format("#<%s: %s>", type, ary.join(", "))
    end
  end

  #
  # irb context
  #
  class Context
    #
    # Arguments:
    #   input_method: nil -- stdin or readline
    #		      String -- File
    #		      other -- using this as InputMethod
    #
    def initialize(irb, main, bind, input_method = nil)
      @irb = irb
      @main = main
      @bind = bind
      @thread = Thread.current if defined? Thread
      @irb_level = 0

      # copy of default configuration
      @ap_name = IRB.conf[:AP_NAME]
      @rc = IRB.conf[:RC]
      @load_modules = IRB.conf[:LOAD_MODULES]

      self.math_mode = IRB.conf[:MATH_MODE]
      @use_readline = IRB.conf[:USE_READLINE]
      @inspect_mode = IRB.conf[:INSPECT_MODE]
      @use_tracer = IRB.conf[:USE_TRACER]
#      @use_loader = IRB.conf[:USE_LOADER]

      self.prompt_mode = IRB.conf[:PROMPT_MODE]
  
      @ignore_sigint = IRB.conf[:IGNORE_SIGINT]
      @ignore_eof = IRB.conf[:IGNORE_EOF]

      @back_trace_limit = IRB.conf[:BACK_TRACE_LIMIT]
      
      debug_level = IRB.conf[:DEBUG_LEVEL]
      @verbose = IRB.conf[:VERBOSE]

      @tracer_initialized = false

      if IRB.conf[:SINGLE_IRB] or !defined?(JobManager)
	@irb_name = IRB.conf[:IRB_NAME]
      else
	@irb_name = "irb#"+IRB.JobManager.n_jobs.to_s
      end
      @irb_path = "(" + @irb_name + ")"

      case input_method
      when nil
	if (use_readline.nil? && IRB.conf[:PROMPT_MODE] != :INF_RUBY ||
	     use_readline?)
	  @io = ReadlineInputMethod.new
	else
	  @io = StdioInputMethod.new
	end
      when String
	@io = FileInputMethod.new(input_method)
	@irb_name = File.basename(input_method)
	@irb_path = input_method
      else
	@io = input_method
      end
    end

    attr :bind, true
    attr :main, true
    attr :thread
    attr :io, true
    
    attr :_
    
    attr :irb
    attr :ap_name
    attr :rc
    attr :load_modules
    attr :irb_name
    attr :irb_path

    attr :math_mode, true
    attr :use_readline, true
    attr :inspect_mode
    attr :use_tracer
#    attr :use_loader

    attr :debug_level
    attr :verbose, true

    attr :prompt_mode
    attr :prompt_i, true
    attr :prompt_s, true
    attr :prompt_c, true
    attr :auto_indent_mode, true
    attr :return_format, true

    attr :ignore_sigint, true
    attr :ignore_eof, true

    attr :back_trace_limit

#    alias use_loader? use_loader
    alias use_tracer? use_tracer
    alias use_readline? use_readline
    alias rc? rc
    alias math? math_mode
    alias verbose? verbose
    alias ignore_sigint? ignore_sigint
    alias ignore_eof? ignore_eof

    def _=(value)
      @_ = value
      eval "_ = IRB.conf[:MAIN_CONTEXT]._", @bind
    end

    def irb_name
      if @irb_level == 0
	@irb_name 
      elsif @irb_name =~ /#[0-9]*$/
	@irb_name + "." + @irb_level.to_s
      else
	@irb_name + "#0." + @irb_level.to_s
      end
    end

    def prompt_mode=(mode)
      @prompt_mode = mode
      pconf = IRB.conf[:PROMPT][mode]
      @prompt_i = pconf[:PROMPT_I]
      @prompt_s = pconf[:PROMPT_S]
      @prompt_c = pconf[:PROMPT_C]
      @return_format = pconf[:RETURN]
      if ai = pconf.include?(:AUTO_INDENT)
	@auto_indent_mode = ai
      else
	@auto_indent_mode = IRB.conf[:AUTO_INDENT]
      end
    end
    
    def inspect?
      @inspect_mode.nil? && !@math_mode or @inspect_mode
    end

    def file_input?
      @io.type == FileInputMethod
    end

    def use_tracer=(opt)
      if opt
	IRB.initialize_tracer
	unless @tracer_initialized
	  Tracer.set_get_line_procs(@irb_path) {
	    |line_no|
	    @io.line(line_no)
	  }
	  @tracer_initialized = true
	end
      elsif !opt && @use_tracer
	Tracer.off
      end
      @use_tracer=opt
    end

    def use_loader
      IRB.conf[:USE_LOADER]
    end

    def use_loader=(opt)
      IRB.conf[:USE_LOADER] = opt
      if opt
	IRB.initialize_loader
      end
      print "Switch to load/require#{unless use_loader; ' non';end} trace mode.\n" if verbose?
      opt
    end

    def inspect_mode=(opt)
      if opt
	@inspect_mode = opt
      else
	@inspect_mode = !@inspect_mode
      end
      print "Switch to#{unless @inspect_mode; ' non';end} inspect mode.\n" if verbose?
      @inspect_mode
    end

    def math_mode=(opt)
      if @math_mode == true && opt == false
	IRB.fail CantRetuenNormalMode
	return
      end

      @math_mode = opt
      if math_mode
	IRB.initialize_mathn
	@main.instance_eval("include Math")
	print "start math mode\n" if verbose?
      end
    end

    def use_readline=(opt)
      @use_readline = opt
      print "use readline module\n" if @use_readline
    end

    def debug_level=(value)
      @debug_level = value
      RubyLex.debug_level = value
      SLex.debug_level = value
    end

    def debug?
      @debug_level > 0
    end

    def change_binding(*main)
      back = [@bind, @main]
      @bind = IRB.workspace_binding(*main)
      unless main.empty?
	@main = eval("self", @bind)
	begin
	  @main.extend ExtendCommand
	rescue
	  print "can't change binding to: ", @main.inspect, "\n"
	  @bind, @main = back
	  return nil
	end
      end
      @irb_level += 1
      begin
	catch(:SU_EXIT) do
	  @irb.eval_input
	end
      ensure
	@irb_level -= 1
 	@bind, @main = back
      end
    end

    alias __exit__ exit
    def exit(ret = 0)
      if @irb_level == 0
	IRB.irb_exit(@irb, ret)
      else
	throw :SU_EXIT, ret
      end
    end

    NOPRINTING_IVARS = ["@_"]
    NO_INSPECTING_IVARS = ["@irb", "@io"]
    IDNAME_IVARS = ["@prompt_mode"]

    alias __inspect__ inspect
    def inspect
      array = []
      for ivar in instance_variables.sort{|e1, e2| e1 <=> e2}
	name = ivar.sub(/^@(.*)$/){$1}
	val = instance_eval(ivar)
	case ivar
	when *NOPRINTING_IVARS
	  next
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

  #
  # IRB extended command
  #
  module Loader; end
  module ExtendCommand
    include Loader

    alias irb_exit_org exit
    def irb_exit(ret = 0)
      irb_context.exit(ret)
    end
    alias exit irb_exit
    alias quit irb_exit

    alias irb_fork fork
    def fork(&block)
      unless irb_fork
	eval "alias exit irb_exit_org"
	instance_eval "alias exit irb_exit_org"
	if iterator?
	  yield
	  exit
	end
      end
    end

    def irb_change_binding(*main)
      irb_context.change_binding(*main)
    end
    alias cb irb_change_binding

    def irb_source(file)
      irb_context.source(file)
    end
    alias source irb_source

    def irb(*obj)
      require "irb/multi-irb"
      IRB.irb(nil, *obj)
    end

    def irb_context
      IRB.conf[:MAIN_CONTEXT]
    end
    alias conf irb_context

    def irb_jobs
      require "irb/multi-irb"
      IRB.JobManager
    end
    alias jobs irb_jobs

    def irb_fg(key)
      require "irb/multi-irb"
      IRB.JobManager.switch(key)
    end
    alias fg irb_fg

    def irb_kill(*keys)
      require "irb/multi-irb"
      IRB.JobManager.kill(*keys)
    end
    alias kill irb_kill
  end

  # Singleton method
  def @CONF.inspect
    IRB.version unless self[:VERSION]

    array = []
    for k, v in sort{|a1, a2| a1[0].id2name <=> a2[0].id2name}
      case k
      when :MAIN_CONTEXT
	next
      when :PROMPT
	s = v.collect{
	  |kk, vv|
	  ss = vv.collect{|kkk, vvv| ":#{kkk.id2name}=>#{vvv.inspect}"}
	  format(":%s=>{%s}", kk.id2name, ss.join(", "))
	}
	array.push format("CONF[:%s]={%s}", k.id2name, s.join(", "))
      else
	array.push format("CONF[:%s]=%s", k.id2name, v.inspect)
      end
    end
    array.join("\n")
  end
end
