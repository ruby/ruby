require "rdoc/parsers/parse_simple"

module RDoc

  # A parser is simple a class that implements
  #
  #   #initialize(file_name, body, options)
  #
  # and
  #
  #   #scan
  #
  # The initialize method takes a file name to be used, the body of the
  # file, and an RDoc::Options object. The scan method is then called
  # to return an appropriately parsed TopLevel code object.
  #
  # The ParseFactory is used to redirect to the correct parser given a filename
  # extension. This magic works because individual parsers have to register 
  # themselves with us as they are loaded in. The do this using the following
  # incantation
  #
  #
  #    require "rdoc/parsers/parsefactory"
  #    
  #    module RDoc
  #    
  #      class XyzParser
  #        extend ParseFactory                  <<<<
  #        parse_files_matching /\.xyz$/        <<<<
  #    
  #        def initialize(file_name, body, options)
  #          ...
  #        end
  #    
  #        def scan
  #          ...
  #        end
  #      end
  #    end
  #
  # Just to make life interesting, if we suspect a plain text file, we
  # also look for a shebang line just in case it's a potential
  # shell script



  module ParserFactory

    @@parsers = []

    Parsers = Struct.new(:regexp, :parser)

    # Record the fact that a particular class parses files that
    # match a given extension

    def parse_files_matching(regexp)
      @@parsers.unshift Parsers.new(regexp, self)
    end

    # Return a parser that can handle a particular extension

    def ParserFactory.can_parse(file_name)
      @@parsers.find {|p| p.regexp.match(file_name) }
    end

    # Alias an extension to another extension. After this call,
    # files ending "new_ext" will be parsed using the same parser
    # as "old_ext"

    def ParserFactory.alias_extension(old_ext, new_ext)
      parser = ParserFactory.can_parse("xxx.#{old_ext}")
      return false unless parser
      @@parsers.unshift Parsers.new(Regexp.new("\\.#{new_ext}$"), parser.parser)
      true
    end

    # Find the correct parser for a particular file name. Return a 
    # SimpleParser for ones that we don't know

    def ParserFactory.parser_for(top_level, file_name, body, options, stats)
      # If no extension, look for shebang
      if file_name !~ /\.\w+$/ && body =~ %r{\A#!(.+)}
        shebang = $1
        case shebang
        when %r{env\s+ruby}, %r{/ruby}
          file_name = "dummy.rb"
        end
      end
      parser_description = can_parse(file_name)
      if parser_description
        parser = parser_description.parser 
      else
        parser = SimpleParser
      end

      parser.new(top_level, file_name, body, options, stats)
    end
  end
end
