# We handle the parsing of options, and subsequently as a singleton
# object to be queried for option values

module RI

  VERSION_STRING = "alpha 0.1"

  class Options
    
    require 'singleton'
    require 'getoptlong'
    
    include Singleton

    # No not use a pager. Writable, because ri sets it if it
    # can't find a pager
    attr_accessor :use_stdout

    # The width of the output line
    attr_reader :width
    
    module OptionList
      
      OPTION_LIST = [
        [ "--help",          "-h",   nil,
         "you're looking at it" ],
             
        [ "--no-pager",      "-T",   nil,
          "Send output directly to stdout." 
        ],

        [ "--width",         "-w",   "output width",
        "set the width of the output" ],

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
      
      def OptionList.usage
        
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
          containing puncuation:

              ri 'Array.[]'
              ri compact\!

          Options:

      EOT
                                
        OPTION_LIST.each do |long, short, arg, desc|
          opt = sprintf("%20s", "#{long}, #{short}")
          oparg = sprintf("%-7s", arg)
          print "#{opt} #{oparg}"
          desc = desc.split("\n")
          if arg.nil? || arg.length < 7  
            puts desc.shift
          else
            puts
          end
          desc.each do |line|
            puts(" "*28 + line)
          end
          puts
        end

        exit 0
      end
  end

    # Parse command line options.

    def parse

      @use_stdout = !STDOUT.tty?
      @width = 72
      
      begin
        
        go = GetoptLong.new(*OptionList.options)
        go.quiet = true
        
        go.each do |opt, arg|
          case opt
          when "--help"      then OptionList.usage
          when "--no-pager"  then @use_stdout = true
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
  end
end

