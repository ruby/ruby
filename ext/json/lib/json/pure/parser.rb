require 'strscan'

module JSON
  module Pure
    # This class implements the JSON parser that is used to parse a JSON string
    # into a Ruby data structure.
    class Parser < StringScanner
      STRING                = /" ((?:[^\x0-\x1f"\\] |
                                  \\["\\\/bfnrt] |
                                  \\u[0-9a-fA-F]{4} |
                                  \\[\x20-\xff])*)
                              "/nx
      INTEGER               = /(-?0|-?[1-9]\d*)/
      FLOAT                 = /(-?
                                (?:0|[1-9]\d*)
                                (?:
                                  \.\d+(?i:e[+-]?\d+) |
                                  \.\d+ |
                                  (?i:e[+-]?\d+)
                                )
                                )/x
      NAN                   = /NaN/
      INFINITY              = /Infinity/
      MINUS_INFINITY        = /-Infinity/
      OBJECT_OPEN           = /\{/
      OBJECT_CLOSE          = /\}/
      ARRAY_OPEN            = /\[/
      ARRAY_CLOSE           = /\]/
      PAIR_DELIMITER        = /:/
      COLLECTION_DELIMITER  = /,/
      TRUE                  = /true/
      FALSE                 = /false/
      NULL                  = /null/
      IGNORE                = %r(
        (?:
         //[^\n\r]*[\n\r]| # line comments
         /\*               # c-style comments
         (?:
          [^*/]|        # normal chars
          /[^*]|        # slashes that do not start a nested comment
          \*[^/]|       # asterisks that do not end this comment
          /(?=\*/)      # single slash before this comment's end 
         )*
           \*/               # the End of this comment
           |[ \t\r\n]+       # whitespaces: space, horicontal tab, lf, cr
        )+
      )mx

      UNPARSED = Object.new

      # Creates a new JSON::Pure::Parser instance for the string _source_.
      #
      # It will be configured by the _opts_ hash. _opts_ can have the following
      # keys:
      # * *max_nesting*: The maximum depth of nesting allowed in the parsed data
      #   structures. Disable depth checking with :max_nesting => false|nil|0,
      #   it defaults to 19.
      # * *allow_nan*: If set to true, allow NaN, Infinity and -Infinity in
      #   defiance of RFC 4627 to be parsed by the Parser. This option defaults
      #   to false.
      # * *create_additions*: If set to false, the Parser doesn't create
      #   additions even if a matchin class and create_id was found. This option
      #   defaults to true.
      def initialize(source, opts = {})
        super
        if !opts.key?(:max_nesting) # defaults to 19
          @max_nesting = 19
        elsif opts[:max_nesting]
          @max_nesting = opts[:max_nesting]
        else
          @max_nesting = 0
        end
        @allow_nan = !!opts[:allow_nan]
        ca = true
        ca = opts[:create_additions] if opts.key?(:create_additions)
        @create_id = ca ? JSON.create_id : nil
      end

      alias source string

      # Parses the current JSON string _source_ and returns the complete data
      # structure as a result.
      def parse
        reset
        obj = nil
        until eos?
          case
          when scan(OBJECT_OPEN)
            obj and raise ParserError, "source '#{peek(20)}' not in JSON!"
            @current_nesting = 1
            obj = parse_object
          when scan(ARRAY_OPEN)
            obj and raise ParserError, "source '#{peek(20)}' not in JSON!"
            @current_nesting = 1
            obj = parse_array
          when skip(IGNORE)
            ;
          else
            raise ParserError, "source '#{peek(20)}' not in JSON!"
          end
        end
        obj or raise ParserError, "source did not contain any JSON!"
        obj
      end

      private

      # Unescape characters in strings.
      UNESCAPE_MAP = Hash.new { |h, k| h[k] = k.chr }
      UNESCAPE_MAP.update({
        ?"  => '"',
        ?\\ => '\\',
        ?/  => '/',
        ?b  => "\b",
        ?f  => "\f",
        ?n  => "\n",
        ?r  => "\r",
        ?t  => "\t",
        ?u  => nil, 
      })

      def parse_string
        if scan(STRING)
          return '' if self[1].empty?
          self[1].gsub(%r((?:\\[\\bfnrt"/]|(?:\\u(?:[A-Fa-f\d]{4}))+|\\[\x20-\xff]))n) do |c|
            if u = UNESCAPE_MAP[$&[1]]
              u
            else # \uXXXX
              bytes = ''
              i = 0
              while c[6 * i] == ?\\ && c[6 * i + 1] == ?u 
                bytes << c[6 * i + 2, 2].to_i(16) << c[6 * i + 4, 2].to_i(16)
                i += 1
              end
              JSON::UTF16toUTF8.iconv(bytes)
            end
          end
        else
          UNPARSED
        end
      rescue Iconv::Failure => e
        raise GeneratorError, "Caught #{e.class}: #{e}"
      end

      def parse_value
        case
        when scan(FLOAT)
          Float(self[1])
        when scan(INTEGER)
          Integer(self[1])
        when scan(TRUE)
          true
        when scan(FALSE)
          false
        when scan(NULL)
          nil
        when (string = parse_string) != UNPARSED
          string
        when scan(ARRAY_OPEN)
          @current_nesting += 1
          ary = parse_array
          @current_nesting -= 1
          ary
        when scan(OBJECT_OPEN)
          @current_nesting += 1
          obj = parse_object
          @current_nesting -= 1
          obj
        when @allow_nan && scan(NAN)
          NaN
        when @allow_nan && scan(INFINITY)
          Infinity
        when @allow_nan && scan(MINUS_INFINITY)
          MinusInfinity
        else
          UNPARSED
        end
      end

      def parse_array
        raise NestingError, "nesting of #@current_nesting is to deep" if
          @max_nesting.nonzero? && @current_nesting > @max_nesting
        result = []
        delim = false
        until eos?
          case
          when (value = parse_value) != UNPARSED
            delim = false
            result << value
            skip(IGNORE)
            if scan(COLLECTION_DELIMITER)
              delim = true
            elsif match?(ARRAY_CLOSE)
              ;
            else
              raise ParserError, "expected ',' or ']' in array at '#{peek(20)}'!"
            end
          when scan(ARRAY_CLOSE)
            if delim
              raise ParserError, "expected next element in array at '#{peek(20)}'!"
            end
            break
          when skip(IGNORE)
            ;
          else
            raise ParserError, "unexpected token in array at '#{peek(20)}'!"
          end
        end
        result
      end

      def parse_object
        raise NestingError, "nesting of #@current_nesting is to deep" if
          @max_nesting.nonzero? && @current_nesting > @max_nesting
        result = {}
        delim = false
        until eos?
          case
          when (string = parse_string) != UNPARSED
            skip(IGNORE)
            unless scan(PAIR_DELIMITER)
              raise ParserError, "expected ':' in object at '#{peek(20)}'!"
            end
            skip(IGNORE)
            unless (value = parse_value).equal? UNPARSED
              result[string] = value
              delim = false
              skip(IGNORE)
              if scan(COLLECTION_DELIMITER)
                delim = true
              elsif match?(OBJECT_CLOSE)
                ;
              else
                raise ParserError, "expected ',' or '}' in object at '#{peek(20)}'!"
              end
            else
              raise ParserError, "expected value in object at '#{peek(20)}'!"
            end
          when scan(OBJECT_CLOSE)
            if delim
              raise ParserError, "expected next name, value pair in object at '#{peek(20)}'!"
            end
            if @create_id and klassname = result[@create_id]
              klass = JSON.deep_const_get klassname
              break unless klass and klass.json_creatable?
              result = klass.json_create(result)
            end
            break
          when skip(IGNORE)
            ;
          else
            raise ParserError, "unexpected token in object at '#{peek(20)}'!"
          end
        end
        result
      end
    end
  end
end
