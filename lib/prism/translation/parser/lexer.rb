# frozen_string_literal: true

require "strscan"

module Prism
  module Translation
    class Parser
      # Accepts a list of prism tokens and converts them into the expected
      # format for the parser gem.
      class Lexer
        # The direct translating of types between the two lexers.
        TYPES = {
          # These tokens should never appear in the output of the lexer.
          EOF: nil,
          MISSING: nil,
          NOT_PROVIDED: nil,
          IGNORED_NEWLINE: nil,
          EMBDOC_END: nil,
          EMBDOC_LINE: nil,
          __END__: nil,

          # These tokens have more or less direct mappings.
          AMPERSAND: :tAMPER2,
          AMPERSAND_AMPERSAND: :tANDOP,
          AMPERSAND_AMPERSAND_EQUAL: :tOP_ASGN,
          AMPERSAND_DOT: :tANDDOT,
          AMPERSAND_EQUAL: :tOP_ASGN,
          BACK_REFERENCE: :tBACK_REF,
          BACKTICK: :tXSTRING_BEG,
          BANG: :tBANG,
          BANG_EQUAL: :tNEQ,
          BANG_TILDE: :tNMATCH,
          BRACE_LEFT: :tLCURLY,
          BRACE_RIGHT: :tRCURLY,
          BRACKET_LEFT: :tLBRACK2,
          BRACKET_LEFT_ARRAY: :tLBRACK,
          BRACKET_LEFT_RIGHT: :tAREF,
          BRACKET_LEFT_RIGHT_EQUAL: :tASET,
          BRACKET_RIGHT: :tRBRACK,
          CARET: :tCARET,
          CARET_EQUAL: :tOP_ASGN,
          CHARACTER_LITERAL: :tCHARACTER,
          CLASS_VARIABLE: :tCVAR,
          COLON: :tCOLON,
          COLON_COLON: :tCOLON2,
          COMMA: :tCOMMA,
          COMMENT: :tCOMMENT,
          CONSTANT: :tCONSTANT,
          DOT: :tDOT,
          DOT_DOT: :tDOT2,
          DOT_DOT_DOT: :tDOT3,
          EMBDOC_BEGIN: :tCOMMENT,
          EMBEXPR_BEGIN: :tSTRING_DBEG,
          EMBEXPR_END: :tSTRING_DEND,
          EMBVAR: :tSTRING_DVAR,
          EQUAL: :tEQL,
          EQUAL_EQUAL: :tEQ,
          EQUAL_EQUAL_EQUAL: :tEQQ,
          EQUAL_GREATER: :tASSOC,
          EQUAL_TILDE: :tMATCH,
          FLOAT: :tFLOAT,
          FLOAT_IMAGINARY: :tIMAGINARY,
          FLOAT_RATIONAL: :tRATIONAL,
          FLOAT_RATIONAL_IMAGINARY: :tIMAGINARY,
          GLOBAL_VARIABLE: :tGVAR,
          GREATER: :tGT,
          GREATER_EQUAL: :tGEQ,
          GREATER_GREATER: :tRSHFT,
          GREATER_GREATER_EQUAL: :tOP_ASGN,
          HEREDOC_START: :tSTRING_BEG,
          HEREDOC_END: :tSTRING_END,
          IDENTIFIER: :tIDENTIFIER,
          INSTANCE_VARIABLE: :tIVAR,
          INTEGER: :tINTEGER,
          INTEGER_IMAGINARY: :tIMAGINARY,
          INTEGER_RATIONAL: :tRATIONAL,
          INTEGER_RATIONAL_IMAGINARY: :tIMAGINARY,
          KEYWORD_ALIAS: :kALIAS,
          KEYWORD_AND: :kAND,
          KEYWORD_BEGIN: :kBEGIN,
          KEYWORD_BEGIN_UPCASE: :klBEGIN,
          KEYWORD_BREAK: :kBREAK,
          KEYWORD_CASE: :kCASE,
          KEYWORD_CLASS: :kCLASS,
          KEYWORD_DEF: :kDEF,
          KEYWORD_DEFINED: :kDEFINED,
          KEYWORD_DO: :kDO,
          KEYWORD_DO_LOOP: :kDO_COND,
          KEYWORD_END: :kEND,
          KEYWORD_END_UPCASE: :klEND,
          KEYWORD_ENSURE: :kENSURE,
          KEYWORD_ELSE: :kELSE,
          KEYWORD_ELSIF: :kELSIF,
          KEYWORD_FALSE: :kFALSE,
          KEYWORD_FOR: :kFOR,
          KEYWORD_IF: :kIF,
          KEYWORD_IF_MODIFIER: :kIF_MOD,
          KEYWORD_IN: :kIN,
          KEYWORD_MODULE: :kMODULE,
          KEYWORD_NEXT: :kNEXT,
          KEYWORD_NIL: :kNIL,
          KEYWORD_NOT: :kNOT,
          KEYWORD_OR: :kOR,
          KEYWORD_REDO: :kREDO,
          KEYWORD_RESCUE: :kRESCUE,
          KEYWORD_RESCUE_MODIFIER: :kRESCUE_MOD,
          KEYWORD_RETRY: :kRETRY,
          KEYWORD_RETURN: :kRETURN,
          KEYWORD_SELF: :kSELF,
          KEYWORD_SUPER: :kSUPER,
          KEYWORD_THEN: :kTHEN,
          KEYWORD_TRUE: :kTRUE,
          KEYWORD_UNDEF: :kUNDEF,
          KEYWORD_UNLESS: :kUNLESS,
          KEYWORD_UNLESS_MODIFIER: :kUNLESS_MOD,
          KEYWORD_UNTIL: :kUNTIL,
          KEYWORD_UNTIL_MODIFIER: :kUNTIL_MOD,
          KEYWORD_WHEN: :kWHEN,
          KEYWORD_WHILE: :kWHILE,
          KEYWORD_WHILE_MODIFIER: :kWHILE_MOD,
          KEYWORD_YIELD: :kYIELD,
          KEYWORD___ENCODING__: :k__ENCODING__,
          KEYWORD___FILE__: :k__FILE__,
          KEYWORD___LINE__: :k__LINE__,
          LABEL: :tLABEL,
          LABEL_END: :tLABEL_END,
          LAMBDA_BEGIN: :tLAMBEG,
          LESS: :tLT,
          LESS_EQUAL: :tLEQ,
          LESS_EQUAL_GREATER: :tCMP,
          LESS_LESS: :tLSHFT,
          LESS_LESS_EQUAL: :tOP_ASGN,
          METHOD_NAME: :tFID,
          MINUS: :tMINUS,
          MINUS_EQUAL: :tOP_ASGN,
          MINUS_GREATER: :tLAMBDA,
          NEWLINE: :tNL,
          NUMBERED_REFERENCE: :tNTH_REF,
          PARENTHESIS_LEFT: :tLPAREN2,
          PARENTHESIS_LEFT_PARENTHESES: :tLPAREN_ARG,
          PARENTHESIS_RIGHT: :tRPAREN,
          PERCENT: :tPERCENT,
          PERCENT_EQUAL: :tOP_ASGN,
          PERCENT_LOWER_I: :tQSYMBOLS_BEG,
          PERCENT_LOWER_W: :tQWORDS_BEG,
          PERCENT_UPPER_I: :tSYMBOLS_BEG,
          PERCENT_UPPER_W: :tWORDS_BEG,
          PERCENT_LOWER_X: :tXSTRING_BEG,
          PLUS: :tPLUS,
          PLUS_EQUAL: :tOP_ASGN,
          PIPE_EQUAL: :tOP_ASGN,
          PIPE: :tPIPE,
          PIPE_PIPE: :tOROP,
          PIPE_PIPE_EQUAL: :tOP_ASGN,
          QUESTION_MARK: :tEH,
          REGEXP_BEGIN: :tREGEXP_BEG,
          REGEXP_END: :tSTRING_END,
          SEMICOLON: :tSEMI,
          SLASH: :tDIVIDE,
          SLASH_EQUAL: :tOP_ASGN,
          STAR: :tSTAR2,
          STAR_EQUAL: :tOP_ASGN,
          STAR_STAR: :tPOW,
          STAR_STAR_EQUAL: :tOP_ASGN,
          STRING_BEGIN: :tSTRING_BEG,
          STRING_CONTENT: :tSTRING_CONTENT,
          STRING_END: :tSTRING_END,
          SYMBOL_BEGIN: :tSYMBEG,
          TILDE: :tTILDE,
          UAMPERSAND: :tAMPER,
          UCOLON_COLON: :tCOLON3,
          UDOT_DOT: :tBDOT2,
          UDOT_DOT_DOT: :tBDOT3,
          UMINUS: :tUMINUS,
          UMINUS_NUM: :tUNARY_NUM,
          UPLUS: :tUPLUS,
          USTAR: :tSTAR,
          USTAR_STAR: :tDSTAR,
          WORDS_SEP: :tSPACE
        }

        # These constants represent flags in our lex state. We really, really
        # don't want to be using them and we really, really don't want to be
        # exposing them as part of our public API. Unfortunately, we don't have
        # another way of matching the exact tokens that the parser gem expects
        # without them. We should find another way to do this, but in the
        # meantime we'll hide them from the documentation and mark them as
        # private constants.
        EXPR_BEG = 0x1 # :nodoc:
        EXPR_LABEL = 0x400 # :nodoc:

        # It is used to determine whether `do` is of the token type `kDO` or `kDO_LAMBDA`.
        #
        # NOTE: In edge cases like `-> (foo = -> (bar) {}) do end`, please note that `kDO` is still returned
        # instead of `kDO_LAMBDA`, which is expected: https://github.com/ruby/prism/pull/3046
        LAMBDA_TOKEN_TYPES = [:kDO_LAMBDA, :tLAMBDA, :tLAMBEG]

        # The `PARENTHESIS_LEFT` token in Prism is classified as either `tLPAREN` or `tLPAREN2` in the Parser gem.
        # The following token types are listed as those classified as `tLPAREN`.
        LPAREN_CONVERSION_TOKEN_TYPES = [
          :kBREAK, :kCASE, :tDIVIDE, :kFOR, :kIF, :kNEXT, :kRETURN, :kUNTIL, :kWHILE, :tAMPER, :tANDOP, :tBANG, :tCOMMA, :tDOT2, :tDOT3,
          :tEQL, :tLPAREN, :tLPAREN2, :tLSHFT, :tNL, :tOP_ASGN, :tOROP, :tPIPE, :tSEMI, :tSTRING_DBEG, :tUMINUS, :tUPLUS
        ]

        private_constant :TYPES, :EXPR_BEG, :EXPR_LABEL, :LAMBDA_TOKEN_TYPES, :LPAREN_CONVERSION_TOKEN_TYPES

        # The Parser::Source::Buffer that the tokens were lexed from.
        attr_reader :source_buffer

        # An array of tuples that contain prism tokens and their associated lex
        # state when they were lexed.
        attr_reader :lexed

        # A hash that maps offsets in bytes to offsets in characters.
        attr_reader :offset_cache

        # Initialize the lexer with the given source buffer, prism tokens, and
        # offset cache.
        def initialize(source_buffer, lexed, offset_cache)
          @source_buffer = source_buffer
          @lexed = lexed
          @offset_cache = offset_cache
        end

        Range = ::Parser::Source::Range # :nodoc:
        private_constant :Range

        # Convert the prism tokens into the expected format for the parser gem.
        def to_a
          tokens = []

          index = 0
          length = lexed.length

          heredoc_identifier_stack = []

          while index < length
            token, state = lexed[index]
            index += 1
            next if %i[IGNORED_NEWLINE __END__ EOF].include?(token.type)

            type = TYPES.fetch(token.type)
            value = token.value
            location = Range.new(source_buffer, offset_cache[token.location.start_offset], offset_cache[token.location.end_offset])

            case type
            when :kDO
              types = tokens.map(&:first)
              nearest_lambda_token_type = types.reverse.find { |type| LAMBDA_TOKEN_TYPES.include?(type) }

              if nearest_lambda_token_type == :tLAMBDA
                type = :kDO_LAMBDA
              end
            when :tCHARACTER
              value.delete_prefix!("?")
              # Character literals behave similar to double-quoted strings. We can use the same escaping mechanism.
              value = unescape_string(value, "?")
            when :tCOMMENT
              if token.type == :EMBDOC_BEGIN
                start_index = index

                while !((next_token = lexed[index][0]) && next_token.type == :EMBDOC_END) && (index < length - 1)
                  value += next_token.value
                  index += 1
                end

                if start_index != index
                  value += next_token.value
                  location = Range.new(source_buffer, offset_cache[token.location.start_offset], offset_cache[lexed[index][0].location.end_offset])
                  index += 1
                end
              else
                value.chomp!
                location = Range.new(source_buffer, offset_cache[token.location.start_offset], offset_cache[token.location.end_offset - 1])
              end
            when :tNL
              value = nil
            when :tFLOAT
              value = parse_float(value)
            when :tIMAGINARY
              value = parse_complex(value)
            when :tINTEGER
              if value.start_with?("+")
                tokens << [:tUNARY_NUM, ["+", Range.new(source_buffer, offset_cache[token.location.start_offset], offset_cache[token.location.start_offset + 1])]]
                location = Range.new(source_buffer, offset_cache[token.location.start_offset + 1], offset_cache[token.location.end_offset])
              end

              value = parse_integer(value)
            when :tLABEL
              value.chomp!(":")
            when :tLABEL_END
              value.chomp!(":")
            when :tLCURLY
              type = :tLBRACE if state == EXPR_BEG | EXPR_LABEL
            when :tLPAREN2
              type = :tLPAREN if tokens.empty? || LPAREN_CONVERSION_TOKEN_TYPES.include?(tokens.dig(-1, 0))
            when :tNTH_REF
              value = parse_integer(value.delete_prefix("$"))
            when :tOP_ASGN
              value.chomp!("=")
            when :tRATIONAL
              value = parse_rational(value)
            when :tSPACE
              value = nil
            when :tSTRING_BEG
              if token.type == :HEREDOC_START
                heredoc_identifier_stack.push(value.match(/<<[-~]?["'`]?(?<heredoc_identifier>.*?)["'`]?\z/)[:heredoc_identifier])
              end
              if ["\"", "'"].include?(value) && (next_token = lexed[index][0]) && next_token.type == :STRING_END
                next_location = token.location.join(next_token.location)
                type = :tSTRING
                value = ""
                location = Range.new(source_buffer, offset_cache[next_location.start_offset], offset_cache[next_location.end_offset])
                index += 1
              elsif ["\"", "'"].include?(value) && (next_token = lexed[index][0]) && next_token.type == :STRING_CONTENT && next_token.value.lines.count <= 1 && (next_next_token = lexed[index + 1][0]) && next_next_token.type == :STRING_END
                next_location = token.location.join(next_next_token.location)
                type = :tSTRING
                value = next_token.value.gsub("\\\\", "\\")
                location = Range.new(source_buffer, offset_cache[next_location.start_offset], offset_cache[next_location.end_offset])
                index += 2
              elsif value.start_with?("<<")
                quote = value[2] == "-" || value[2] == "~" ? value[3] : value[2]
                if quote == "`"
                  type = :tXSTRING_BEG
                  value = "<<`"
                else
                  value = "<<#{quote == "'" || quote == "\"" ? quote : "\""}"
                end
              end
            when :tSTRING_CONTENT
              unless (lines = token.value.lines).one?
                start_offset = offset_cache[token.location.start_offset]
                lines.map do |line|
                  newline = line.end_with?("\r\n") ? "\r\n" : "\n"
                  chomped_line = line.chomp
<<<<<<< HEAD
                  if match = chomped_line.match(/(?<backslashes>\\+)\z/)
                    adjustment = match[:backslashes].size / 2
                    adjusted_line = chomped_line.delete_suffix("\\" * adjustment)
                    if match[:backslashes].size.odd?
                      adjusted_line.delete_suffix!("\\")
                      adjustment += 2
                    else
                      adjusted_line << newline
                    end
=======
                  backslash_count = chomped_line[/\\{1,}\z/]&.length || 0
                  is_interpolation = interpolation?(quote_stack.last)
                  is_percent_array = percent_array?(quote_stack.last)

                  if backslash_count.odd? && (is_interpolation || is_percent_array)
                    if is_percent_array
                      # Remove the last backslash, keep potential newlines
                      current_line << line.sub(/(\\)(\r?\n)\z/, '\2')
                      adjustment += 1
                    else
                      chomped_line.delete_suffix!("\\")
                      current_line << chomped_line
                      adjustment += 2
                    end
                    # If the string ends with a line continuation emit the remainder
                    emit = index == lines.count - 1
>>>>>>> b6554ad64e (Fix parser translator tokens for backslashes in single-quoted strings and word arrays)
                  else
                    adjusted_line = line
                    adjustment = 0
                  end

                  end_offset = start_offset + adjusted_line.bytesize + adjustment
                  tokens << [:tSTRING_CONTENT, [adjusted_line, Range.new(source_buffer, offset_cache[start_offset], offset_cache[end_offset])]]
                  start_offset = end_offset
                end
                next
              end
            when :tSTRING_DVAR
              value = nil
            when :tSTRING_END
              if token.type == :HEREDOC_END && value.end_with?("\n")
                newline_length = value.end_with?("\r\n") ? 2 : 1
                value = heredoc_identifier_stack.pop
                location = Range.new(source_buffer, offset_cache[token.location.start_offset], offset_cache[token.location.end_offset - newline_length])
              elsif token.type == :REGEXP_END
                value = value[0]
                location = Range.new(source_buffer, offset_cache[token.location.start_offset], offset_cache[token.location.start_offset + 1])
              end
            when :tSYMBEG
              if (next_token = lexed[index][0]) && next_token.type != :STRING_CONTENT && next_token.type != :EMBEXPR_BEGIN && next_token.type != :EMBVAR && next_token.type != :STRING_END
                next_location = token.location.join(next_token.location)
                type = :tSYMBOL
                value = next_token.value
                value = { "~@" => "~", "!@" => "!" }.fetch(value, value)
                location = Range.new(source_buffer, offset_cache[next_location.start_offset], offset_cache[next_location.end_offset])
                index += 1
              end
            when :tFID
              if !tokens.empty? && tokens.dig(-1, 0) == :kDEF
                type = :tIDENTIFIER
              end
            when :tXSTRING_BEG
              if (next_token = lexed[index][0]) && next_token.type != :STRING_CONTENT && next_token.type != :STRING_END
                type = :tBACK_REF2
              end
            end

            tokens << [type, [value, location]]

            if token.type == :REGEXP_END
              tokens << [:tREGEXP_OPT, [token.value[1..], Range.new(source_buffer, offset_cache[token.location.start_offset + 1], offset_cache[token.location.end_offset])]]
            end
          end

          tokens
        end

        private

        # Parse an integer from the string representation.
        def parse_integer(value)
          Integer(value)
        rescue ArgumentError
          0
        end

        # Parse a float from the string representation.
        def parse_float(value)
          Float(value)
        rescue ArgumentError
          0.0
        end

        # Parse a complex from the string representation.
        def parse_complex(value)
          value.chomp!("i")

          if value.end_with?("r")
            Complex(0, parse_rational(value))
          elsif value.start_with?(/0[BbOoDdXx]/)
            Complex(0, parse_integer(value))
          else
            Complex(0, value)
          end
        rescue ArgumentError
          0i
        end

        # Parse a rational from the string representation.
        def parse_rational(value)
          value.chomp!("r")

          if value.start_with?(/0[BbOoDdXx]/)
            Rational(parse_integer(value))
          else
            Rational(value)
          end
        rescue ArgumentError
          0r
        end

        # Wonky heredoc tab/spaces rules.
        # https://github.com/ruby/prism/blob/v1.3.0/src/prism.c#L10548-L10558
        def calculate_heredoc_whitespace(heredoc_token_index)
          next_token_index = heredoc_token_index
          nesting_level = 0
          previous_line = -1
          result = Float::MAX

          while (lexed[next_token_index] && next_token = lexed[next_token_index][0])
            next_token_index += 1
            next_next_token = lexed[next_token_index] && lexed[next_token_index][0]

            # String content inside nested heredocs and interpolation is ignored
            if next_token.type == :HEREDOC_START || next_token.type == :EMBEXPR_BEGIN
              nesting_level += 1
            elsif next_token.type == :HEREDOC_END || next_token.type == :EMBEXPR_END
              nesting_level -= 1
              # When we encountered the matching heredoc end, we can exit
              break if nesting_level == -1
            elsif next_token.type == :STRING_CONTENT && nesting_level == 0
              common_whitespace = 0
              next_token.value[/^\s*/].each_char do |char|
                if char == "\t"
                  common_whitespace = (common_whitespace / 8 + 1) * 8;
                else
                  common_whitespace += 1
                end
              end

              is_first_token_on_line = next_token.location.start_line != previous_line
              # Whitespace is significant if followed by interpolation
              whitespace_only = common_whitespace == next_token.value.length && next_next_token&.location&.start_line != next_token.location.start_line
              if is_first_token_on_line && !whitespace_only && common_whitespace < result
                result = common_whitespace
                previous_line = next_token.location.start_line
              end
            end
          end
          result
        end

        # Wonky heredoc tab/spaces rules.
        # https://github.com/ruby/prism/blob/v1.3.0/src/prism.c#L16528-L16545
        def trim_heredoc_whitespace(string, heredoc)
          trimmed_whitespace = 0
          trimmed_characters = 0
          while (string[trimmed_characters] == "\t" || string[trimmed_characters] == " ") && trimmed_whitespace < heredoc.common_whitespace
            if string[trimmed_characters] == "\t"
              trimmed_whitespace = (trimmed_whitespace / 8 + 1) * 8;
              break if trimmed_whitespace > heredoc.common_whitespace
            else
              trimmed_whitespace += 1
            end
            trimmed_characters += 1
          end

          string[trimmed_characters..]
        end

        # Escape sequences that have special and should appear unescaped in the resulting string.
        ESCAPES = {
          "a" => "\a", "b" => "\b", "e" => "\e", "f" => "\f",
          "n" => "\n", "r" => "\r", "s" => "\s", "t" => "\t",
          "v" => "\v", "\\" => "\\"
        }.freeze
        private_constant :ESCAPES

        # When one of these delimiters is encountered, then the other
        # one is allowed to be escaped as well.
        DELIMITER_SYMETRY = { "[" => "]", "(" => ")", "{" => "}", "<" => ">" }.freeze
        private_constant :DELIMITER_SYMETRY

        # Apply Ruby string escaping rules
        def unescape_string(string, quote)
          # In single-quoted heredocs, everything is taken literally.
          return string if quote == "<<'"

          # TODO: Implement regexp escaping
          return string if quote == "/" || quote.start_with?("%r")

          # OPTIMIZATION: Assume that few strings need escaping to speed up the common case.
          return string unless string.include?("\\")

          if interpolation?(quote)
            # Appending individual escape sequences may force the string out of its intended
            # encoding. Start out with binary and force it back later.
            result = "".b

            scanner = StringScanner.new(string)
            while (skipped = scanner.skip_until(/\\/))
              # Append what was just skipped over, excluding the found backslash.
              result << string.byteslice(scanner.pos - skipped, skipped - 1)

              # Simple single-character escape sequences like \n
              if (replacement = ESCAPES[scanner.peek(1)])
                result << replacement
                scanner.pos += 1
              elsif (octal = scanner.check(/[0-7]{1,3}/))
                # \nnn
                # NOTE: When Ruby 3.4 is required, this can become result.append_as_bytes(chr)
                result << octal.to_i(8).chr.b
                scanner.pos += octal.bytesize
              elsif (hex = scanner.check(/x([0-9a-fA-F]{1,2})/))
                # \xnn
                result << hex[1..].to_i(16).chr.b
                scanner.pos += hex.bytesize
              elsif (unicode = scanner.check(/u([0-9a-fA-F]{4})/))
                # \unnnn
                result << unicode[1..].hex.chr(Encoding::UTF_8).b
                scanner.pos += unicode.bytesize
              elsif scanner.peek(3) == "u{}"
                # https://github.com/whitequark/parser/issues/856
                scanner.pos += 3
              elsif (unicode_parts = scanner.check(/u{.*}/))
                # \u{nnnn ...}
                unicode_parts[2..-2].split.each do |unicode|
                  result << unicode.hex.chr(Encoding::UTF_8).b
                end
                scanner.pos += unicode_parts.bytesize
              end
            end

            # Add remainging chars
            result << string.byteslice(scanner.pos..)

            result.force_encoding(source_buffer.source.encoding)

            result
          else
            if quote == "'"
              delimiter = "'"
            else
              delimiter = quote[2]
            end

            delimiters = Regexp.escape("#{delimiter}#{DELIMITER_SYMETRY[delimiter]}")
            string.gsub(/\\([\\#{delimiters}])/, '\1')
          end
        end

        # Determine if characters preceeded by a backslash should be escaped or not
        def interpolation?(quote)
          quote != "'" && !quote.start_with?("%q", "%w", "%i")
        end

        # Determine if the string is part of a %-style array.
        def percent_array?(quote)
          quote.start_with?("%w", "%W", "%i", "%I")
        end
      end
    end
  end
end
