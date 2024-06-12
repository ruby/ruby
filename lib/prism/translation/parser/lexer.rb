# frozen_string_literal: true

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
          PARENTHESIS_LEFT: :tLPAREN,
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
          USTAR_STAR: :tPOW,
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

        private_constant :TYPES, :EXPR_BEG, :EXPR_LABEL

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
            when :tCHARACTER
              value.delete_prefix!("?")
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
                  if match = chomped_line.match(/(?<backslashes>\\+)\z/)
                    adjustment = match[:backslashes].size / 2
                    adjusted_line = chomped_line.delete_suffix("\\" * adjustment)
                    if match[:backslashes].size.odd?
                      adjusted_line.delete_suffix!("\\")
                      adjustment += 2
                    else
                      adjusted_line << newline
                    end
                  else
                    adjusted_line = line
                    adjustment = 0
                  end

                  end_offset = start_offset + adjusted_line.length + adjustment
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
      end
    end
  end
end
