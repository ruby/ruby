# frozen_string_literal: false
#
#   irb/init.rb - irb initialize module
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

module IRB # :nodoc:

  # initialize config
  def IRB.setup(ap_path, argv: ::ARGV)
    IRB.init_config(ap_path)
    IRB.init_error
    IRB.parse_opts(argv: argv)
    IRB.run_config
    IRB.load_modules

    unless @CONF[:PROMPT][@CONF[:PROMPT_MODE]]
      fail UndefinedPromptMode, @CONF[:PROMPT_MODE]
    end
  end

  # @CONF default setting
  def IRB.init_config(ap_path)
    # class instance variables
    @TRACER_INITIALIZED = false

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

    @CONF[:USE_SINGLELINE] = false unless defined?(ReadlineInputMethod)
    @CONF[:USE_COLORIZE] = true
    @CONF[:INSPECT_MODE] = true
    @CONF[:USE_TRACER] = false
    @CONF[:USE_LOADER] = false
    @CONF[:IGNORE_SIGINT] = true
    @CONF[:IGNORE_EOF] = false
    @CONF[:ECHO] = nil
    @CONF[:ECHO_ON_ASSIGNMENT] = nil
    @CONF[:VERBOSE] = nil

    @CONF[:EVAL_HISTORY] = nil
    @CONF[:SAVE_HISTORY] = 1000

    @CONF[:BACK_TRACE_LIMIT] = 16

    @CONF[:PROMPT] = {
      :NULL => {
        :PROMPT_I => nil,
        :PROMPT_N => nil,
        :PROMPT_S => nil,
        :PROMPT_C => nil,
        :RETURN => "%s\n"
      },
      :DEFAULT => {
        :PROMPT_I => "%N(%m):%03n:%i> ",
        :PROMPT_N => "%N(%m):%03n:%i> ",
        :PROMPT_S => "%N(%m):%03n:%i%l ",
        :PROMPT_C => "%N(%m):%03n:%i* ",
        :RETURN => "=> %s\n"
      },
      :CLASSIC => {
        :PROMPT_I => "%N(%m):%03n:%i> ",
        :PROMPT_N => "%N(%m):%03n:%i> ",
        :PROMPT_S => "%N(%m):%03n:%i%l ",
        :PROMPT_C => "%N(%m):%03n:%i* ",
        :RETURN => "%s\n"
      },
      :SIMPLE => {
        :PROMPT_I => ">> ",
        :PROMPT_N => ">> ",
        :PROMPT_S => "%l> ",
        :PROMPT_C => "?> ",
        :RETURN => "=> %s\n"
      },
      :INF_RUBY => {
        :PROMPT_I => "%N(%m):%03n:%i> ",
        :PROMPT_N => nil,
        :PROMPT_S => nil,
        :PROMPT_C => nil,
        :RETURN => "%s\n",
        :AUTO_INDENT => true
      },
      :XMP => {
        :PROMPT_I => nil,
        :PROMPT_N => nil,
        :PROMPT_S => nil,
        :PROMPT_C => nil,
        :RETURN => "    ==>%s\n"
      }
    }

    @CONF[:PROMPT_MODE] = (STDIN.tty? ? :DEFAULT : :NULL)
    @CONF[:AUTO_INDENT] = true

    @CONF[:CONTEXT_MODE] = 3 # use binding in function on TOPLEVEL_BINDING
    @CONF[:SINGLE_IRB] = false

    @CONF[:LC_MESSAGES] = Locale.new

    @CONF[:AT_EXIT] = []
  end

  def IRB.init_error
    @CONF[:LC_MESSAGES].load("irb/error.rb")
  end

  # option analyzing
  def IRB.parse_opts(argv: ::ARGV)
    load_path = []
    while opt = argv.shift
      case opt
      when "-f"
        @CONF[:RC] = false
      when "-d"
        $DEBUG = true
        $VERBOSE = true
      when "-w"
        $VERBOSE = true
      when /^-W(.+)?/
        opt = $1 || argv.shift
        case opt
        when "0"
          $VERBOSE = nil
        when "1"
          $VERBOSE = false
        else
          $VERBOSE = true
        end
      when /^-r(.+)?/
        opt = $1 || argv.shift
        @CONF[:LOAD_MODULES].push opt if opt
      when /^-I(.+)?/
        opt = $1 || argv.shift
        load_path.concat(opt.split(File::PATH_SEPARATOR)) if opt
      when '-U'
        set_encoding("UTF-8", "UTF-8")
      when /^-E(.+)?/, /^--encoding(?:=(.+))?/
        opt = $1 || argv.shift
        set_encoding(*opt.split(':', 2))
      when "--inspect"
        if /^-/ !~ argv.first
          @CONF[:INSPECT_MODE] = argv.shift
        else
          @CONF[:INSPECT_MODE] = true
        end
      when "--noinspect"
        @CONF[:INSPECT_MODE] = false
      when "--singleline", "--readline", "--legacy"
        @CONF[:USE_SINGLELINE] = true
      when "--nosingleline", "--noreadline"
        @CONF[:USE_SINGLELINE] = false
      when "--multiline", "--reidline"
        @CONF[:USE_MULTILINE] = true
      when "--nomultiline", "--noreidline"
        @CONF[:USE_MULTILINE] = false
      when "--echo"
        @CONF[:ECHO] = true
      when "--noecho"
        @CONF[:ECHO] = false
      when "--echo-on-assignment"
        @CONF[:ECHO_ON_ASSIGNMENT] = true
      when "--noecho-on-assignment"
        @CONF[:ECHO_ON_ASSIGNMENT] = false
      when "--verbose"
        @CONF[:VERBOSE] = true
      when "--noverbose"
        @CONF[:VERBOSE] = false
      when "--colorize"
        @CONF[:USE_COLORIZE] = true
      when "--nocolorize"
        @CONF[:USE_COLORIZE] = false
      when /^--prompt-mode(?:=(.+))?/, /^--prompt(?:=(.+))?/
        opt = $1 || argv.shift
        prompt_mode = opt.upcase.tr("-", "_").intern
        @CONF[:PROMPT_MODE] = prompt_mode
      when "--noprompt"
        @CONF[:PROMPT_MODE] = :NULL
      when "--inf-ruby-mode"
        @CONF[:PROMPT_MODE] = :INF_RUBY
      when "--sample-book-mode", "--simple-prompt"
        @CONF[:PROMPT_MODE] = :SIMPLE
      when "--tracer"
        @CONF[:USE_TRACER] = true
      when /^--back-trace-limit(?:=(.+))?/
        @CONF[:BACK_TRACE_LIMIT] = ($1 || argv.shift).to_i
      when /^--context-mode(?:=(.+))?/
        @CONF[:CONTEXT_MODE] = ($1 || argv.shift).to_i
      when "--single-irb"
        @CONF[:SINGLE_IRB] = true
      when "-v", "--version"
        print IRB.version, "\n"
        exit 0
      when "-h", "--help"
        require_relative "help"
        IRB.print_usage
        exit 0
      when "--"
        if opt = argv.shift
          @CONF[:SCRIPT] = opt
          $0 = opt
        end
        break
      when /^-/
        fail UnrecognizedSwitch, opt
      else
        @CONF[:SCRIPT] = opt
        $0 = opt
        break
      end
    end
    load_path.collect! do |path|
      /\A\.\// =~ path ? path : File.expand_path(path)
    end
    $LOAD_PATH.unshift(*load_path)

  end

  # running config
  def IRB.run_config
    if @CONF[:RC]
      begin
        load rc_file
      rescue LoadError, Errno::ENOENT
      rescue # StandardError, ScriptError
        print "load error: #{rc_file}\n"
        print $!.class, ": ", $!, "\n"
        for err in $@[0, $@.size - 2]
          print "\t", err, "\n"
        end
      end
    end
  end

  IRBRC_EXT = "rc"
  def IRB.rc_file(ext = IRBRC_EXT)
    if !@CONF[:RC_NAME_GENERATOR]
      rc_file_generators do |rcgen|
        @CONF[:RC_NAME_GENERATOR] ||= rcgen
        if File.exist?(rcgen.call(IRBRC_EXT))
          @CONF[:RC_NAME_GENERATOR] = rcgen
          break
        end
      end
    end
    case rc_file = @CONF[:RC_NAME_GENERATOR].call(ext)
    when String
      return rc_file
    else
      fail IllegalRCNameGenerator
    end
  end

  # enumerate possible rc-file base name generators
  def IRB.rc_file_generators
    if irbrc = ENV["IRBRC"]
      yield proc{|rc| rc == "rc" ? irbrc : irbrc+rc}
    end
    if home = ENV["HOME"]
      yield proc{|rc| home+"/.irb#{rc}"}
    end
    current_dir = Dir.pwd
    yield proc{|rc| current_dir+"/.irb#{rc}"}
    yield proc{|rc| current_dir+"/irb#{rc.sub(/\A_?/, '.')}"}
    yield proc{|rc| current_dir+"/_irb#{rc}"}
    yield proc{|rc| current_dir+"/$irb#{rc}"}
  end

  # loading modules
  def IRB.load_modules
    for m in @CONF[:LOAD_MODULES]
      begin
        require m
      rescue LoadError => err
        warn "#{err.class}: #{err}", uplevel: 0
      end
    end
  end


  DefaultEncodings = Struct.new(:external, :internal)
  class << IRB
    private
    def set_encoding(extern, intern = nil)
      verbose, $VERBOSE = $VERBOSE, nil
      Encoding.default_external = extern unless extern.nil? || extern.empty?
      Encoding.default_internal = intern unless intern.nil? || intern.empty?
      @CONF[:ENCODINGS] = IRB::DefaultEncodings.new(extern, intern)
      [$stdin, $stdout, $stderr].each do |io|
        io.set_encoding(extern, intern)
      end
      @CONF[:LC_MESSAGES].instance_variable_set(:@encoding, extern)
    ensure
      $VERBOSE = verbose
    end
  end
end
