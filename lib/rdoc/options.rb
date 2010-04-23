require 'optparse'

require 'rdoc/ri/paths'

##
# RDoc::Options handles the parsing and storage of options

class RDoc::Options

  ##
  # Character-set

  attr_reader :charset

  ##
  # Files matching this pattern will be excluded

  attr_accessor :exclude

  ##
  # The list of files to be processed

  attr_accessor :files

  ##
  # Scan newer sources than the flag file if true.

  attr_reader :force_update

  ##
  # Description of the output generator (set with the <tt>-fmt</tt> option)

  attr_accessor :generator

  ##
  # Formatter to mark up text with

  attr_accessor :formatter

  ##
  # Name of the file, class or module to display in the initial index page (if
  # not specified the first file we encounter is used)

  attr_accessor :main_page

  ##
  # The name of the output directory

  attr_accessor :op_dir

  ##
  # Is RDoc in pipe mode?

  attr_accessor :pipe

  ##
  # Array of directories to search for files to satisfy an :include:

  attr_reader :rdoc_include

  ##
  # Include private and protected methods in the output?

  attr_accessor :show_all

  ##
  # Include the '#' at the front of hyperlinked instance method names

  attr_reader :show_hash

  ##
  # The number of columns in a tab

  attr_reader :tab_width

  ##
  # Template to be used when generating output

  attr_reader :template

  ##
  # Documentation title

  attr_reader :title

  ##
  # Verbosity, zero means quiet

  attr_accessor :verbosity

  ##
  # URL of web cvs frontend

  attr_reader :webcvs

  def initialize # :nodoc:
    require 'rdoc/rdoc'
    @op_dir = nil
    @show_all = false
    @main_page = nil
    @exclude = []
    @generators = RDoc::RDoc::GENERATORS
    @generator = RDoc::Generator::Darkfish
    @generator_name = nil
    @rdoc_include = []
    @title = nil
    @template = nil
    @show_hash = false
    @tab_width = 8
    @force_update = true
    @verbosity = 1
    @pipe = false

    @webcvs = nil

    @charset = 'utf-8'
  end

  ##
  # Parse command line options.

  def parse(argv)
    ignore_invalid = true

    opts = OptionParser.new do |opt|
      opt.program_name = File.basename $0
      opt.version = RDoc::VERSION
      opt.release = nil
      opt.summary_indent = ' ' * 4
      opt.banner = <<-EOF
Usage: #{opt.program_name} [options] [names...]

  Files are parsed, and the information they contain collected, before any
  output is produced. This allows cross references between all files to be
  resolved. If a name is a directory, it is traversed. If no names are
  specified, all Ruby files in the current directory (and subdirectories) are
  processed.

  How RDoc generates output depends on the output formatter being used, and on
  the options you give.

  - Darkfish creates frameless HTML output by Michael Granger.
  - ri creates ri data files

  RDoc understands the following file formats:

      EOF

      parsers = Hash.new { |h,parser| h[parser] = [] }

      RDoc::Parser.parsers.each do |regexp, parser|
        parsers[parser.name.sub('RDoc::Parser::', '')] << regexp.source
      end

      parsers.sort.each do |parser, regexp|
        opt.banner << "  - #{parser}: #{regexp.join ', '}\n"
      end

      opt.separator nil
      opt.separator "Parsing Options:"
      opt.separator nil

      opt.on("--all", "-a",
             "Include all methods (not just public) in",
             "the output.") do |value|
        @show_all = value
      end

      opt.separator nil

      opt.on("--exclude=PATTERN", "-x", Regexp,
             "Do not process files or directories",
             "matching PATTERN.") do |value|
        @exclude << value
      end

      opt.separator nil

      opt.on("--extension=NEW=OLD", "-E",
             "Treat files ending with .new as if they",
             "ended with .old. Using '-E cgi=rb' will",
             "cause xxx.cgi to be parsed as a Ruby file.") do |value|
        new, old = value.split(/=/, 2)

        unless new and old then
          raise OptionParser::InvalidArgument, "Invalid parameter to '-E'"
        end

        unless RDoc::Parser.alias_extension old, new then
          raise OptionParser::InvalidArgument, "Unknown extension .#{old} to -E"
        end
      end

      opt.separator nil

      opt.on("--[no-]force-update", "-U",
             "Forces rdoc to scan all sources even if",
             "newer than the flag file.") do |value|
        @force_update = value
      end

      opt.separator nil

      opt.on("--pipe",
             "Convert RDoc on stdin to HTML") do
        @pipe = true
      end

      opt.separator nil
      opt.separator "Generator Options:"
      opt.separator nil

      opt.on("--charset=CHARSET", "-c",
             "Specifies the output HTML character-set.") do |value|
        @charset = value
      end

      opt.separator nil

      generator_text = @generators.keys.map { |name| "  #{name}" }.sort

      opt.on("--fmt=FORMAT", "--format=FORMAT", "-f", @generators.keys,
             "Set the output formatter.  One of:", *generator_text) do |value|
        @generator_name = value.downcase
        setup_generator
      end

      opt.separator nil

      opt.on("--include=DIRECTORIES", "-i", Array,
             "Set (or add to) the list of directories to",
             "be searched when satisfying :include:",
             "requests. Can be used more than once.") do |value|
        @rdoc_include.concat value.map { |dir| dir.strip }
      end

      opt.separator nil

      opt.on("--main=NAME", "-m",
             "NAME will be the initial page displayed.") do |value|
        @main_page = value
      end

      opt.separator nil

      opt.on("--output=DIR", "--op", "-o",
             "Set the output directory.") do |value|
        @op_dir = value
      end

      opt.separator nil

      opt.on("--show-hash", "-H",
             "A name of the form #name in a comment is a",
             "possible hyperlink to an instance method",
             "name. When displayed, the '#' is removed",
             "unless this option is specified.") do |value|
        @show_hash = value
      end

      opt.separator nil

      opt.on("--tab-width=WIDTH", "-w", OptionParser::DecimalInteger,
             "Set the width of tab characters.") do |value|
        @tab_width = value
      end

      opt.separator nil

      opt.on("--template=NAME", "-T",
             "Set the template used when generating",
             "output.") do |value|
        @template = value
      end

      opt.separator nil

      opt.on("--title=TITLE", "-t",
             "Set TITLE as the title for HTML output.") do |value|
        @title = value
      end

      opt.separator nil

      opt.on("--webcvs=URL", "-W",
             "Specify a URL for linking to a web frontend",
             "to CVS. If the URL contains a '\%s', the",
             "name of the current file will be",
             "substituted; if the URL doesn't contain a",
             "'\%s', the filename will be appended to it.") do |value|
        @webcvs = value
      end

      opt.separator nil

      opt.on("-d", "--diagram", "Prevents -d from tripping --debug")

      opt.separator nil
      opt.separator "ri Generator Options:"
      opt.separator nil

      opt.on("--ri", "-r",
             "Generate output for use by `ri`. The files",
             "are stored in the '.rdoc' directory under",
             "your home directory unless overridden by a",
             "subsequent --op parameter, so no special",
             "privileges are needed.") do |value|
        @generator_name = "ri"
        @op_dir ||= RDoc::RI::Paths::HOMEDIR
        setup_generator
      end

      opt.separator nil

      opt.on("--ri-site", "-R",
             "Generate output for use by `ri`. The files",
             "are stored in a site-wide directory,",
             "making them accessible to others, so",
             "special privileges are needed.") do |value|
        @generator_name = "ri"
        @op_dir = RDoc::RI::Paths::SITEDIR
        setup_generator
      end

      opt.separator nil
      opt.separator "Generic Options:"
      opt.separator nil

      opt.on("-D", "--[no-]debug",
             "Displays lots on internal stuff.") do |value|
        $DEBUG_RDOC = value
      end

      opt.on("--[no-]ignore-invalid",
             "Ignore invalid options and continue.") do |value|
        ignore_invalid = value
      end

      opt.on("--quiet", "-q",
             "Don't show progress as we parse.") do |value|
        @verbosity = 0
      end

      opt.on("--verbose", "-v",
             "Display extra progress as we parse.") do |value|
        @verbosity = 2
      end

      opt.separator nil
    end

    argv.insert(0, *ENV['RDOCOPT'].split) if ENV['RDOCOPT']
    ignored = []

    begin
      opts.parse! argv
    rescue OptionParser::InvalidArgument, OptionParser::InvalidOption => e
      if ignore_invalid then
        ignored << e.args.join(' ')
        retry
      else
        $stderr.puts opts
        $stderr.puts
        $stderr.puts e
        exit 1
      end
    end

    unless ignored.empty? or quiet then
      $stderr.puts "invalid options: #{ignored.join ', '}"
      $stderr.puts '(invalid options are ignored)'
    end

    @op_dir ||= 'doc'
    @files = argv.dup

    @rdoc_include << "." if @rdoc_include.empty?

    if @exclude.empty? then
      @exclude = nil
    else
      @exclude = Regexp.new(@exclude.join("|"))
    end

    check_files

    # If no template was specified, use the default template for the output
    # formatter

    @template ||= @generator_name
  end

  ##
  # Set the title, but only if not already set. This means that a title set
  # from the command line trumps one set in a source file

  def title=(string)
    @title ||= string
  end

  ##
  # Don't display progress as we process the files

  def quiet
    @verbosity.zero?
  end

  def quiet=(bool)
    @verbosity = bool ? 0 : 1
  end

  private

  ##
  # Set up an output generator for the format in @generator_name

  def setup_generator
    @generator = @generators[@generator_name]

    unless @generator then
      raise OptionParser::InvalidArgument, "Invalid output formatter"
    end
  end

  ##
  # Check that the files on the command line exist

  def check_files
    @files.each do |f|
      stat = File.stat f rescue next
      raise RDoc::Error, "file '#{f}' not readable" unless stat.readable?
    end
  end

end

