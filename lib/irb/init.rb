#
#   irb/init.rb - irb initialize module
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

  # initialize config
  def IRB.initialize(ap_path)
    IRB.init_config(ap_path)
    IRB.init_error
    IRB.run_config
  end

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

    @CONF[:CONTEXT_MODE] = 3 # use binding in function on TOPLEVEL_BINDING
    @CONF[:SINGLE_IRB] = false

#    @CONF[:LC_MESSAGES] = "en"
    @CONF[:LC_MESSAGES] = Locale.new
    
    @CONF[:DEBUG_LEVEL] = 1
    @CONF[:VERBOSE] = true
  end

  def IRB.init_error
    @CONF[:LC_MESSAGES].load("irb/error.rb")
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
	exit 0
      when "-h", "--help"
	require "irb/help"
	IRB.print_usage
	exit 0
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
end
