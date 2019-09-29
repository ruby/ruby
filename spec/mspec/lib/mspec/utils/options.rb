require 'mspec/version'

MSPEC_HOME = File.expand_path('../../../..', __FILE__)

class MSpecOption
  attr_reader :short, :long, :arg, :description, :block

  def initialize(short, long, arg, description, block)
    @short       = short
    @long        = long
    @arg         = arg
    @description = description
    @block       = block
  end

  def arg?
    @arg != nil
  end

  def match?(opt)
    opt == @short or opt == @long
  end
end

# MSpecOptions provides a parser for command line options. It also
# provides a composable set of options from which the runner scripts
# can select for their particular functionality.
class MSpecOptions
  # Raised if incorrect or incomplete formats are passed to #on.
  class OptionError < Exception; end

  # Raised if an unrecognized option is encountered.
  class ParseError < Exception; end

  attr_accessor :config, :banner, :width, :options

  def initialize(banner="", width=30, config=nil)
    @banner   = banner
    @config   = config
    @width    = width
    @options  = []
    @doc      = []
    @extra    = []
    @on_extra = lambda { |x|
      raise ParseError, "Unrecognized option: #{x}" if x[0] == ?-
      @extra << x
    }

    yield self if block_given?
  end

  # Registers an option. Acceptable formats for arguments are:
  #
  #  on "-a", "description"
  #  on "-a", "--abdc", "description"
  #  on "-a", "ARG", "description"
  #  on "--abdc", "ARG", "description"
  #  on "-a", "--abdc", "ARG", "description"
  #
  # If an block is passed, it will be invoked when the option is
  # matched. Not passing a block is permitted, but nonsensical.
  def on(*args, &block)
    raise OptionError, "option and description are required" if args.size < 2

    description = args.pop
    short, long, argument = nil
    args.each do |arg|
      if arg[0] == ?-
        if arg[1] == ?-
          long = arg
        else
          short = arg
        end
      else
        argument = arg
      end
    end

    add short, long, argument, description, block
  end

  # Adds documentation text for an option and adds an +MSpecOption+
  # instance to the list of registered options.
  def add(short, long, arg, description, block)
    s = short ? short.dup : "  "
    s += (short ? ", " : "  ") if long
    doc "   #{s}#{long} #{arg}".ljust(@width-1) + " #{description}"
    @options << MSpecOption.new(short, long, arg, description, block)
  end

  # Searches all registered options to find a match for +opt+. Returns
  # +nil+ if no registered options match.
  def match?(opt)
    @options.find { |o| o.match? opt }
  end

  # Processes an option. Calles the #on_extra block (or default) for
  # unrecognized options. For registered options, possibly fetches an
  # argument and invokes the option's block if it is not nil.
  def process(argv, entry, opt, arg)
    unless option = match?(opt)
      @on_extra[entry]
    else
      if option.arg?
        arg = argv.shift if arg.nil?
        raise ParseError, "No argument provided for #{opt}" unless arg
        option.block[arg] if option.block
      else
        option.block[] if option.block
      end
    end
    option
  end

  # Splits a string at +n+ characters into the +opt+ and the +rest+.
  # The +arg+ is set to +nil+ if +rest+ is an empty string.
  def split(str, n)
    opt  = str[0, n]
    rest = str[n, str.size]
    arg  = rest == "" ? nil : rest
    return opt, arg, rest
  end

  # Parses an array of command line entries, calling blocks for
  # registered options.
  def parse(argv=ARGV)
    argv = Array(argv).dup

    while entry = argv.shift
      # collect everything that is not an option
      if entry[0] != ?- or entry.size < 2
        @on_extra[entry]
        next
      end

      # this is a long option
      if entry[1] == ?-
        opt, arg = entry.split "="
        process argv, entry, opt, arg
        next
      end

      # disambiguate short option group from short option with argument
      opt, arg, rest = split entry, 2

      # process first option
      option = process argv, entry, opt, arg
      next unless option and !option.arg?

      # process the rest of the options
      while rest.size > 0
        opt, arg, rest = split rest, 1
        opt = "-" + opt
        option = process argv, opt, opt, arg
        break if !option or option.arg?
      end
    end

    @extra
  rescue ParseError => e
    puts self
    puts e
    exit 1
  end

  # Adds a string of documentation text inline in the text generated
  # from the options. See #on and #add.
  def doc(str)
    @doc << str
  end

  # Convenience method for providing -v, --version options.
  def version(version, &block)
    show = block || lambda { puts "#{File.basename $0} #{version}"; exit }
    on "-v", "--version", "Show version", &show
  end

  # Convenience method for providing -h, --help options.
  def help(&block)
    help = block || lambda { puts self; exit 1 }
    on "-h", "--help", "Show this message", &help
  end

  # Stores a block that will be called with unrecognized options
  def on_extra(&block)
    @on_extra = block
  end

  # Returns a string representation of the options and doc strings.
  def to_s
    @banner + "\n\n" + @doc.join("\n") + "\n"
  end

  # The methods below provide groups of options that
  # are composed by the particular runners to provide
  # their functionality

  def configure(&block)
    on("-B", "--config", "FILE",
       "Load FILE containing configuration options", &block)
  end

  def targets
    on("-t", "--target", "TARGET",
       "Implementation to run the specs, where TARGET is:") do |t|
      case t
      when 'r', 'ruby'
        config[:target] = 'ruby'
      when 'x', 'rubinius'
        config[:target] = './bin/rbx'
      when 'X', 'rbx'
        config[:target] = 'rbx'
      when 'j', 'jruby'
        config[:target] = 'jruby'
      when 'i','ironruby'
        config[:target] = 'ir'
      when 'm','maglev'
        config[:target] = 'maglev-ruby'
      when 't','topaz'
        config[:target] = 'topaz'
      when 'o','opal'
        mspec_lib = File.expand_path('../../../', __FILE__)
        config[:target] = "./bin/opal -syaml -sfileutils -rnodejs -rnodejs/require -rnodejs/yaml -rprocess -Derror -I#{mspec_lib} -I./lib/ -I. "
      else
        config[:target] = t
      end
    end

    doc ""
    doc "     r or ruby         invokes ruby in PATH"
    doc "     x or rubinius     invokes ./bin/rbx"
    doc "     X or rbx          invokes rbx in PATH"
    doc "     j or jruby        invokes jruby in PATH"
    doc "     i or ironruby     invokes ir in PATH"
    doc "     m or maglev       invokes maglev-ruby in PATH"
    doc "     t or topaz        invokes topaz in PATH"
    doc "     o or opal         invokes ./bin/opal with options"
    doc "     full path to EXE  invokes EXE directly\n"

    on("-T", "--target-opt", "OPT",
       "Pass OPT as a flag to the target implementation") do |t|
      config[:flags] << t
    end
    on("-I", "--include", "DIR",
       "Pass DIR through as the -I option to the target") do |d|
      config[:loadpath] << "-I#{d}"
    end
    on("-r", "--require", "LIBRARY",
       "Pass LIBRARY through as the -r option to the target") do |f|
      config[:requires] << "-r#{f}"
    end
  end

  def formatters
    on("-f", "--format", "FORMAT",
       "Formatter for reporting, where FORMAT is one of:") do |o|
      require 'mspec/runner/formatters'
      case o
      when 's', 'spec', 'specdoc'
        config[:formatter] = SpecdocFormatter
      when 'h', 'html'
        config[:formatter] = HtmlFormatter
      when 'd', 'dot', 'dotted'
        config[:formatter] = DottedFormatter
      when 'b', 'describe'
        config[:formatter] = DescribeFormatter
      when 'f', 'file'
        config[:formatter] = FileFormatter
      when 'u', 'unit', 'unitdiff'
        config[:formatter] = UnitdiffFormatter
      when 'm', 'summary'
        config[:formatter] = SummaryFormatter
      when 'a', '*', 'spin'
        config[:formatter] = SpinnerFormatter
      when 't', 'method'
        config[:formatter] = MethodFormatter
      when 'y', 'yaml'
        config[:formatter] = YamlFormatter
      when 'p', 'profile'
        config[:formatter] = ProfileFormatter
      when 'j', 'junit'
        config[:formatter] = JUnitFormatter
      else
        abort "Unknown format: #{o}\n#{@parser}" unless File.exist?(o)
        require File.expand_path(o)
        if Object.const_defined?(:CUSTOM_MSPEC_FORMATTER)
          config[:formatter] = CUSTOM_MSPEC_FORMATTER
        else
          abort "You must define CUSTOM_MSPEC_FORMATTER in your custom formatter file"
        end
      end
    end

    doc ""
    doc "       s, spec, specdoc         SpecdocFormatter"
    doc "       h, html,                 HtmlFormatter"
    doc "       d, dot, dotted           DottedFormatter"
    doc "       f, file                  FileFormatter"
    doc "       u, unit, unitdiff        UnitdiffFormatter"
    doc "       m, summary               SummaryFormatter"
    doc "       a, *, spin               SpinnerFormatter"
    doc "       t, method                MethodFormatter"
    doc "       y, yaml                  YamlFormatter"
    doc "       p, profile               ProfileFormatter"
    doc "       j, junit                 JUnitFormatter\n"

    on("-o", "--output", "FILE",
       "Write formatter output to FILE") do |f|
      config[:output] = f
    end
  end

  def filters
    on("-e", "--example", "STR",
       "Run examples with descriptions matching STR") do |o|
      config[:includes] << o
    end
    on("-E", "--exclude", "STR",
       "Exclude examples with descriptions matching STR") do |o|
      config[:excludes] << o
    end
    on("-p", "--pattern", "PATTERN",
       "Run examples with descriptions matching PATTERN") do |o|
      config[:patterns] << Regexp.new(o)
    end
    on("-P", "--excl-pattern", "PATTERN",
       "Exclude examples with descriptions matching PATTERN") do |o|
      config[:xpatterns] << Regexp.new(o)
    end
    on("-g", "--tag", "TAG",
       "Run examples with descriptions matching ones tagged with TAG") do |o|
      config[:tags] << o
    end
    on("-G", "--excl-tag", "TAG",
       "Exclude examples with descriptions matching ones tagged with TAG") do |o|
      config[:xtags] << o
    end
    on("-w", "--profile", "FILE",
       "Run examples for methods listed in the profile FILE") do |f|
      config[:profiles] << f
    end
    on("-W", "--excl-profile", "FILE",
       "Exclude examples for methods listed in the profile FILE") do |f|
      config[:xprofiles] << f
    end
  end

  def chdir
    on("-C", "--chdir", "DIR",
       "Change the working directory to DIR before running specs") do |d|
      Dir.chdir d
    end
  end

  def prefix
    on("--prefix", "STR", "Prepend STR when resolving spec file names") do |p|
      config[:prefix] = p
    end
  end

  def pretend
    on("-Z", "--dry-run",
       "Invoke formatters and other actions, but don't execute the specs") do
      MSpec.register_mode :pretend
    end
  end

  def unguarded
    on("--unguarded", "Turn off all guards") do
      MSpec.register_mode :unguarded
    end
    on("--no-ruby_bug", "Turn off the ruby_bug guard") do
      MSpec.register_mode :no_ruby_bug
    end
  end

  def randomize
    on("-H", "--random",
       "Randomize the list of spec files") do
      MSpec.randomize
    end
  end

  def repeat
    on("-R", "--repeat", "NUMBER",
       "Repeatedly run an example NUMBER times") do |o|
      MSpec.repeat = Integer(o)
    end
  end

  def verbose
    on("-V", "--verbose", "Output the name of each file processed") do
      obj = Object.new
      def obj.start
        @width = MSpec.retrieve(:files).inject(0) { |max, f| f.size > max ? f.size : max }
      end
      def obj.load
        file = MSpec.retrieve :file
        STDERR.print "\n#{file.ljust(@width)}"
      end
      MSpec.register :start, obj
      MSpec.register :load, obj
    end

    on("-m", "--marker", "MARKER",
       "Output MARKER for each file processed") do |o|
      obj = Object.new
      obj.instance_variable_set :@marker, o
      def obj.load
        STDERR.print @marker
      end
      MSpec.register :load, obj
    end
  end

  def interrupt
    on("--int-spec", "Control-C interupts the current spec only") do
      config[:abort] = false
    end
  end

  def timeout
    on("--timeout", "TIMEOUT", "Abort if a spec takes longer than TIMEOUT seconds") do |timeout|
      require 'mspec/runner/actions/timeout'
      timeout = Float(timeout)
      TimeoutAction.new(timeout).register
    end
  end

  def verify
    on("--report-on", "GUARD", "Report specs guarded by GUARD") do |g|
      MSpec.register_mode :report_on
      SpecGuard.guards << g.to_sym
    end
    on("-O", "--report", "Report guarded specs") do
      MSpec.register_mode :report
    end
    on("-Y", "--verify",
       "Verify that guarded specs pass and fail as expected") do
      MSpec.register_mode :verify
    end
  end

  def action_filters
    on("-K", "--action-tag", "TAG",
       "Spec descriptions marked with TAG will trigger the specified action") do |o|
      config[:atags] << o
    end
    on("-S", "--action-string", "STR",
       "Spec descriptions matching STR will trigger the specified action") do |o|
      config[:astrings] << o
    end
  end

  def actions
    on("--spec-debug",
       "Invoke the debugger when a spec description matches (see -K, -S)") do
      config[:debugger] = true
    end
  end

  def debug
    on("-d", "--debug",
       "Set MSpec debugging flag for more verbose output") do
      $MSPEC_DEBUG = true
    end
  end

  def all
    # Generated with:
    # puts File.read(__FILE__).scan(/def (\w+).*\n\s*on\(/)
    configure {}
    targets
    formatters
    filters
    chdir
    prefix
    pretend
    unguarded
    randomize
    repeat
    verbose
    interrupt
    verify
    action_filters
    actions
    debug
  end
end
