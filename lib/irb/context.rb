#
#   irb/context.rb - irb context
#   	$Release Version: 0.7.3$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#
#   
#
module IRB
  class Context
    #
    # Arguments:
    #   input_method: nil -- stdin or readline
    #		      String -- File
    #		      other -- using this as InputMethod
    #
    def initialize(irb, workspace = nil, input_method = nil)
      @irb = irb
      if workspace
	@workspace = workspace
      else
	@workspace = WorkSpace.new unless workspace
      end
      @thread = Thread.current if defined? Thread
      @irb_level = 0

      # copy of default configuration
      @ap_name = IRB.conf[:AP_NAME]
      @rc = IRB.conf[:RC]
      @load_modules = IRB.conf[:LOAD_MODULES]

      self.math_mode = IRB.conf[:MATH_MODE]
      @use_readline = IRB.conf[:USE_READLINE]
      @inspect_mode = IRB.conf[:INSPECT_MODE]
      self.use_tracer = IRB.conf[:USE_TRACER]
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

    def main
      @workspace.main
    end

    attr_accessor :workspace
    attr_reader :thread
    attr_accessor :io
    
    attr_reader :_
    
    attr_accessor :irb
    attr_accessor :ap_name
    attr_accessor :rc
    attr_accessor :load_modules
    attr_accessor :irb_name
    attr_accessor :irb_path

    attr_accessor :math_mode
    attr_accessor :use_readline
    attr_reader :inspect_mode
    attr_reader :use_tracer
#    attr :use_loader

    attr_reader :debug_level
    attr_accessor :verbose

    attr_reader :prompt_mode
    attr_accessor :prompt_i
    attr_accessor :prompt_s
    attr_accessor :prompt_c
    attr_accessor :auto_indent_mode
    attr_accessor :return_format

    attr_accessor :ignore_sigint
    attr_accessor :ignore_eof

    attr_accessor :back_trace_limit

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
      @workspace.evaluate "_ = IRB.conf[:MAIN_CONTEXT]._"
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
	main.instance_eval("include Math")
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

    def change_binding(*_main)
      back = @workspace
      @workspace = WorkSpace.new(*_main)
      unless _main.empty?
	begin
	  main.extend ExtendCommand
	rescue
	  print "can't change binding to: ", main.inspect, "\n"
	  @workspace = back
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
 	@workspace = back
      end
    end
    alias change_workspace change_binding


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
end
