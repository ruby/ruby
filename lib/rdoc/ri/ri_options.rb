# We handle the parsing of options, and subsequently as a singleton
# object to be queried for option values

module RI

  require 'rdoc/ri/ri_display'

  VERSION_STRING = "ri v1.0.1 - 20041108"

  class Options
    
    require 'singleton'
    require 'getoptlong'
    
    include Singleton

    # No not use a pager. Writable, because ri sets it if it
    # can't find a pager
    attr_accessor :use_stdout

    # should we just display a class list and exit
    attr_reader :list_classes

    # should we display a list of all names
    attr_reader :list_names

    # The width of the output line
    attr_reader :width

    # the formatting we apply to the output
    attr_reader :formatter

    # the directory we search for original documentation
    attr_reader :doc_dir

    module OptionList
      
      OPTION_LIST = [
        [ "--help",          "-h",   nil,
         "you're looking at it" ],

        [ "--classes",      "-c",   nil,
          "Display the names of classes and modules we\n" +
          "know about"],

        [ "--doc-dir",      "-d",   "<dirname>",
          "A directory to search for documentation. If not\n"+
          "specified, we search the standard rdoc/ri directories."],
                                                           
        [ "--format",       "-f",   "<name>",
         "Format to use when displaying output:\n" +
         "   " + RI::TextFormatter.list + "\n" +
         "Use 'bs' (backspace) with most pager programs.\n" +
         "To use ANSI, either also use the -T option, or\n" +
         "tell your pager to allow control characters\n" +
         "(for example using the -R option to less)"],

        [ "--list-names",    "-l",   nil,
          "List all the names known to RDoc, one per line"
        ],

        [ "--no-pager",      "-T",   nil,
          "Send output directly to stdout." 
        ],

        [ "--width",         "-w",   "output width",
        "Set the width of the output" ],

        [ "--version",       "-v",   nil,
         "Display the version of ri"
        ],

      ]

      def OptionList.options
        OPTION_LIST.map do |long, short, arg,|
          [ long, 
           short, 
           arg ? GetoptLong::REQUIRED_ARGUMENT : GetoptLong::NO_ARGUMENT 
          ]
        end
      end


      def OptionList.strip_output(text)
        text =~ /^\s+/
        leading_spaces = $&
        text.gsub!(/^#{leading_spaces}/, '')
        $stdout.puts text
      end
      
      
      # Show an error and exit
      
      def OptionList.error(msg)
        $stderr.puts
        $stderr.puts msg
        $stderr.puts "\nFor help on options, try 'ri --help'\n\n"
        exit 1
      end
      
      # Show usage and exit
      
      def OptionList.usage(short_form=false)
        
        puts
        puts(RI::VERSION_STRING)
        puts
        
        name = File.basename($0)
        OptionList.strip_output(<<-EOT)
          Usage:

            #{name} [options]  [names...]

          Display information on Ruby classes, modules, and methods.
          Give the names of classes or methods to see their documentation.
          Partial names may be given: if the names match more than
          one entity, a list will be shown, otherwise details on
          that entity will be displayed.

          Nested classes and modules can be specified using the normal
          Name::Name notation, and instance methods can be distinguished
          from class methods using "." (or "#") instead of "::".

          For example:

              ri  File
              ri  File.new
              ri  F.n
              ri  zip

          Note that shell quoting may be required for method names
          containing punctuation:

              ri 'Array.[]'
              ri compact\\!

        EOT

        if short_form
          puts "For help on options, type 'ri -h'"
          puts "For a list of classes I know about, type 'ri -c'"
        else
          puts "Options:\n\n"
          OPTION_LIST.each do|long, short, arg, desc|
            opt = sprintf("%15s", "#{long}, #{short}")
            if arg
              opt << " " << arg
            end
            print opt
            desc = desc.split("\n")
            if opt.size < 17
              print " "*(18-opt.size)
              puts desc.shift
            else
              puts
            end
            desc.each do |line|
              puts(" "*18 + line)
            end
            puts
          end
          puts "Options may also be passed in the 'RI' environment variable"
          exit 0
        end
      end
    end

    # Show the version and exit
    def show_version
      puts VERSION_STRING
      exit(0)
    end


    def initialize
      @use_stdout   = !STDOUT.tty?
      @width        = 72
      @formatter    = RI::TextFormatter.for("plain") 
      @list_classes = false
      @list_names   = false
    end


    # Parse command line options.

    def parse(args)
    
      old_argv = ARGV.dup
#      if ENV["RI"]
#        ARGV.replace(ENV["RI"].split.concat(ARGV))
#      end

     ARGV.replace(args)

      begin

        go = GetoptLong.new(*OptionList.options)
        go.quiet = true

        go.each do |opt, arg|
          case opt
          when "--help"       then OptionList.usage
          when "--version"    then show_version
          when "--list-names" then @list_names = true
          when "--no-pager"   then @use_stdout = true
          when "--classes"    then @list_classes = true
          when "--doc-dir"
            if File.directory?(arg)
              @doc_dir = arg
            else
              $stderr.puts "Invalid directory: #{arg}"
              exit 1
            end

          when "--format"
            @formatter = RI::TextFormatter.for(arg)
            unless @formatter
              $stderr.print "Invalid formatter (should be one of "
              $stderr.puts RI::TextFormatter.list + ")"
              exit 1
            end
          when "--width"
            begin
              @width = Integer(arg)
            rescue 
              $stderr.puts "Invalid width: '#{arg}'"
              exit 1
            end
          end
        end

      rescue GetoptLong::InvalidOption, GetoptLong::MissingArgument => error
        OptionList.error(error.message)

      end
    end

    # Return the doc_dir as an array, or nil if no overriding doc dir was given
    def paths
      defined?(@doc_dir) ? [ @doc_dir ] : nil
    end

    # Return an instance of the displayer (the thing that actually writes
    # the information). This allows us to load in new displayer classes
    # at runtime (for example to help with IDE integration)
    
    def displayer
      ::RiDisplay.new(self)
    end
  end

end

