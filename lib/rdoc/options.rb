# We handle the parsing of options, and subsequently as a singleton
# object to be queried for option values

require "rdoc/ri/paths"
require 'optparse'

class RDoc::Options

  ##
  # Should the output be placed into a single file

  attr_reader :all_one_file

  ##
  # Character-set

  attr_reader :charset

  ##
  # URL of stylesheet

  attr_reader :css

  ##
  # Should diagrams be drawn

  attr_reader :diagram

  ##
  # Files matching this pattern will be excluded

  attr_accessor :exclude

  ##
  # Additional attr_... style method flags

  attr_reader :extra_accessor_flags

  ##
  # Pattern for additional attr_... style methods

  attr_accessor :extra_accessors

  ##
  # Should we draw fileboxes in diagrams

  attr_reader :fileboxes

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
  # image format for diagrams

  attr_reader :image_format

  ##
  # Include line numbers in the source listings

  attr_reader :include_line_numbers

  ##
  # Should source code be included inline, or displayed in a popup

  attr_accessor :inline_source

  ##
  # Name of the file, class or module to display in the initial index page (if
  # not specified the first file we encounter is used)

  attr_accessor :main_page

  ##
  # Merge into classes of the same name when generating ri

  attr_reader :merge

  ##
  # The name of the output directory

  attr_accessor :op_dir

  ##
  # The name to use for the output

  attr_accessor :op_name

  ##
  # Are we promiscuous about showing module contents across multiple files

  attr_reader :promiscuous

  ##
  # Array of directories to search for files to satisfy an :include:

  attr_reader :rdoc_include

  ##
  # Include private and protected methods in the output

  attr_accessor :show_all

  ##
  # Include the '#' at the front of hyperlinked instance method names

  attr_reader :show_hash

  ##
  # The number of columns in a tab

  attr_reader :tab_width

  ##
  # template to be used when generating output

  attr_reader :template

  ##
  # Template class for file generation
  #--
  # HACK around dependencies in lib/rdoc/generator/html.rb

  attr_accessor :template_class # :nodoc:

  ##
  # Documentation title

  attr_reader :title

  ##
  # Verbosity, zero means quiet

  attr_accessor :verbosity

  ##
  # URL of web cvs frontend

  attr_reader :webcvs

  def initialize(generators = {}) # :nodoc:
    @op_dir = "doc"
    @op_name = nil
    @show_all = false
    @main_page = nil
    @merge = false
    @exclude = []
    @generators = generators
    @generator_name = 'html'
    @generator = @generators[@generator_name]
    @rdoc_include = []
    @title = nil
    @template = nil
    @template_class = nil
    @diagram = false
    @fileboxes = false
    @show_hash = false
    @image_format = 'png'
    @inline_source = false
    @all_one_file = false
    @tab_width = 8
    @include_line_numbers = false
    @extra_accessor_flags = {}
    @promiscuous = false
    @force_update = false
    @verbosity = 1

    @css = nil
    @webcvs = nil

    @charset = 'utf-8'
  end

  ##
  # Parse command line options.

  def parse(argv)
    accessors = []

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

  - HTML output is normally produced into a number of separate files
    (one per class, module, and file, along with various indices).
    These files will appear in the directory given by the --op
    option (doc/ by default).

  - XML output by default is written to standard output. If a
    --opname option is given, the output will instead be written
    to a file with that name in the output directory.

  - .chm files (Windows help files) are written in the --op directory.
    If an --opname parameter is present, that name is used, otherwise
    the file will be called rdoc.chm.
      EOF

      opt.separator nil
      opt.separator "Options:"
      opt.separator nil

      opt.on("--accessor=ACCESSORS", "-A", Array,
             "A comma separated list of additional class",
             "methods that should be treated like",
             "'attr_reader' and friends.",
             " ",
             "Option may be repeated.",
             " ",
             "Each accessorname may have '=text'",
             "appended, in which case that text appears",
             "where the r/w/rw appears for normal.",
             "accessors") do |value|
        value.each do |accessor|
          if accessor =~ /^(\w+)(=(.*))?$/
            accessors << $1
            @extra_accessor_flags[$1] = $3
          end
        end
      end

      opt.separator nil

      opt.on("--all", "-a",
             "Include all methods (not just public) in",
             "the output.") do |value|
        @show_all = value
      end

      opt.separator nil

      opt.on("--charset=CHARSET", "-c",
             "Specifies the output HTML character-set.") do |value|
        @charset = value
      end

      opt.separator nil

      opt.on("--debug", "-D",
             "Displays lots on internal stuff.") do |value|
        $DEBUG_RDOC = value
      end

      opt.separator nil

      opt.on("--diagram", "-d",
             "Generate diagrams showing modules and",
             "classes. You need dot V1.8.6 or later to",
             "use the --diagram option correctly. Dot is",
             "available from http://graphviz.org") do |value|
        check_diagram
        @diagram = true
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

        unless RDoc::ParserFactory.alias_extension old, new then
          raise OptionParser::InvalidArgument, "Unknown extension .#{old} to -E"
        end
      end

      opt.separator nil

      opt.on("--fileboxes", "-F",
             "Classes are put in boxes which represents",
             "files, where these classes reside. Classes",
             "shared between more than one file are",
             "shown with list of files that are sharing",
             "them. Silently discarded if --diagram is",
             "not given.") do |value|
        @fileboxes = value
      end

      opt.separator nil

      opt.on("--force-update", "-U",
             "Forces rdoc to scan all sources even if",
             "newer than the flag file.") do |value|
        @force_update = value
      end

      opt.separator nil

      opt.on("--fmt=FORMAT", "--format=FORMAT", "-f", @generators.keys,
             "Set the output formatter.") do |value|
        @generator_name = value.downcase
        setup_generator
      end

      opt.separator nil

      image_formats = %w[gif png jpg jpeg]
      opt.on("--image-format=FORMAT", "-I", image_formats,
             "Sets output image format for diagrams. Can",
             "be #{image_formats.join ', '}. If this option",
             "is omitted, png is used. Requires",
             "diagrams.") do |value|
        @image_format = value
      end

      opt.separator nil

      opt.on("--include=DIRECTORIES", "-i", Array,
             "set (or add to) the list of directories to",
             "be searched when satisfying :include:",
             "requests. Can be used more than once.") do |value|
        @rdoc_include.concat value.map { |dir| dir.strip }
      end

      opt.separator nil

      opt.on("--inline-source", "-S",
             "Show method source code inline, rather than",
             "via a popup link.") do |value|
        @inline_source = value
      end

      opt.separator nil

      opt.on("--line-numbers", "-N",
             "Include line numbers in the source code.") do |value|
        @include_line_numbers = value
      end

      opt.separator nil

      opt.on("--main=NAME", "-m",
             "NAME will be the initial page displayed.") do |value|
        @main_page = value
      end

      opt.separator nil

      opt.on("--merge", "-M",
             "When creating ri output, merge previously",
             "processed classes into previously",
             "documented classes of the same name.") do |value|
        @merge = value
      end

      opt.separator nil

      opt.on("--one-file", "-1",
             "Put all the output into a single file.") do |value|
        @all_one_file = value
        @inline_source = value if value
        @template = 'one_page_html'
      end

      opt.separator nil

      opt.on("--op=DIR", "-o",
             "Set the output directory.") do |value|
        @op_dir = value
      end

      opt.separator nil

      opt.on("--opname=NAME", "-n",
             "Set the NAME of the output. Has no effect",
             "for HTML.") do |value|
        @op_name = value
      end

      opt.separator nil

      opt.on("--promiscuous", "-p",
             "When documenting a file that contains a",
             "module or class also defined in other",
             "files, show all stuff for that module or",
             "class in each files page. By default, only",
             "show stuff defined in that particular file.") do |value|
        @promiscuous = value
      end

      opt.separator nil

      opt.on("--quiet", "-q",
             "Don't show progress as we parse.") do |value|
        @verbosity = 0
      end

      opt.on("--verbose", "-v",
             "Display extra progress as we parse.") do |value|
        @verbosity = 2
      end


      opt.separator nil

      opt.on("--ri", "-r",
             "Generate output for use by `ri`. The files",
             "are stored in the '.rdoc' directory under",
             "your home directory unless overridden by a",
             "subsequent --op parameter, so no special",
             "privileges are needed.") do |value|
        @generator_name = "ri"
        @op_dir = RDoc::RI::Paths::HOMEDIR
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

      opt.on("--ri-system", "-Y",
             "Generate output for use by `ri`. The files",
             "are stored in a site-wide directory,",
             "making them accessible to others, so",
             "special privileges are needed.  This",
             "option is intended to be used during Ruby",
             "installation.") do |value|
        @generator_name = "ri"
        @op_dir = RDoc::RI::Paths::SYSDIR
        setup_generator
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

      opt.on("--style=URL", "-s",
             "Specifies the URL of a separate stylesheet.") do |value|
        @css = value
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
    end

    argv.insert(0, *ENV['RDOCOPT'].split) if ENV['RDOCOPT']

    opts.parse! argv

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

    # Generate a regexp from the accessors
    unless accessors.empty? then
      re = '^(' + accessors.map { |a| Regexp.quote a }.join('|') + ')$'
      @extra_accessors = Regexp.new re
    end

  rescue OptionParser::InvalidArgument, OptionParser::InvalidOption => e
    puts opts
    puts
    puts e
    exit 1
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

    if @generator_name == "xml" then
      @all_one_file = true
      @inline_source = true
    end
  end

  # Check that the right version of 'dot' is available.  Unfortunately this
  # doesn't work correctly under Windows NT, so we'll bypass the test under
  # Windows.

  def check_diagram
    return if RUBY_PLATFORM =~ /mswin|cygwin|mingw|bccwin/

    ok = false
    ver = nil

    IO.popen "dot -V 2>&1" do |io|
      ver = io.read
      if ver =~ /dot.+version(?:\s+gviz)?\s+(\d+)\.(\d+)/ then
        ok = ($1.to_i > 1) || ($1.to_i == 1 && $2.to_i >= 8)
      end
    end

    unless ok then
      if ver =~ /^dot.+version/ then
        $stderr.puts "Warning: You may need dot V1.8.6 or later to use\n",
          "the --diagram option correctly. You have:\n\n   ",
          ver,
          "\nDiagrams might have strange background colors.\n\n"
      else
        $stderr.puts "You need the 'dot' program to produce diagrams.",
          "(see http://www.research.att.com/sw/tools/graphviz/)\n\n"
        exit
      end
    end
  end

  ##
  # Check that the files on the command line exist

  def check_files
    @files.each do |f|
      stat = File.stat f
      raise RDoc::Error, "file '#{f}' not readable" unless stat.readable?
    end
  end

end

