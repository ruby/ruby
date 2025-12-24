# rbs_inline: enabled
# frozen_string_literal: true

require "strscan"

module Lrama
  class Lexer
    module Token
      class UserCode < Base
        attr_accessor :tag #: Lexer::Token::Tag

        # @rbs () -> Array[Lrama::Grammar::Reference]
        def references
          @references ||= _references
        end

        private

        # @rbs () -> Array[Lrama::Grammar::Reference]
        def _references
          scanner = StringScanner.new(s_value)
          references = [] #: Array[Grammar::Reference]

          until scanner.eos? do
            case
            when reference = scan_reference(scanner)
              references << reference
            when scanner.scan(/\/\*/)
              scanner.scan_until(/\*\//)
            else
              scanner.getch
            end
          end

          references
        end

        # @rbs (StringScanner scanner) -> Lrama::Grammar::Reference?
        def scan_reference(scanner)
          start = scanner.pos
          if scanner.scan(/
            # $ references
            # It need to wrap an identifier with brackets to use ".-" for identifiers
            \$(<[a-zA-Z0-9_]+>)?(?:
              (\$)                            # $$, $<long>$
            | (\d+)                           # $1, $2, $<long>1
            | ([a-zA-Z_][a-zA-Z0-9_]*)        # $foo, $expr, $<long>program (named reference without brackets)
            | \[([a-zA-Z_.][-a-zA-Z0-9_.]*)\] # $[expr.right], $[expr-right], $<long>[expr.right] (named reference with brackets)
            )
          |
            # @ references
            # It need to wrap an identifier with brackets to use ".-" for identifiers
            @(?:
              (\$)                            # @$
            | (\d+)                           # @1
            | ([a-zA-Z_][a-zA-Z0-9_]*)        # @foo, @expr (named reference without brackets)
            | \[([a-zA-Z_.][-a-zA-Z0-9_.]*)\] # @[expr.right], @[expr-right]  (named reference with brackets)
            )
          |
            # $: references
            \$:
            (?:
              (\$)                            # $:$
            | (\d+)                           # $:1
            | ([a-zA-Z_][a-zA-Z0-9_]*)        # $:foo, $:expr (named reference without brackets)
            | \[([a-zA-Z_.][-a-zA-Z0-9_.]*)\] # $:[expr.right], $:[expr-right] (named reference with brackets)
            )
          /x)
            case
            # $ references
            when scanner[2] # $$, $<long>$
              tag = scanner[1] ? Lrama::Lexer::Token::Tag.new(s_value: scanner[1]) : nil
              return Lrama::Grammar::Reference.new(type: :dollar, name: "$", ex_tag: tag, first_column: start, last_column: scanner.pos)
            when scanner[3] # $1, $2, $<long>1
              tag = scanner[1] ? Lrama::Lexer::Token::Tag.new(s_value: scanner[1]) : nil
              return Lrama::Grammar::Reference.new(type: :dollar, number: Integer(scanner[3]), index: Integer(scanner[3]), ex_tag: tag, first_column: start, last_column: scanner.pos)
            when scanner[4] # $foo, $expr, $<long>program (named reference without brackets)
              tag = scanner[1] ? Lrama::Lexer::Token::Tag.new(s_value: scanner[1]) : nil
              return Lrama::Grammar::Reference.new(type: :dollar, name: scanner[4], ex_tag: tag, first_column: start, last_column: scanner.pos)
            when scanner[5] # $[expr.right], $[expr-right], $<long>[expr.right] (named reference with brackets)
              tag = scanner[1] ? Lrama::Lexer::Token::Tag.new(s_value: scanner[1]) : nil
              return Lrama::Grammar::Reference.new(type: :dollar, name: scanner[5], ex_tag: tag, first_column: start, last_column: scanner.pos)

            # @ references
            when scanner[6] # @$
              return Lrama::Grammar::Reference.new(type: :at, name: "$", first_column: start, last_column: scanner.pos)
            when scanner[7] # @1
              return Lrama::Grammar::Reference.new(type: :at, number: Integer(scanner[7]), index: Integer(scanner[7]), first_column: start, last_column: scanner.pos)
            when scanner[8] # @foo, @expr (named reference without brackets)
              return Lrama::Grammar::Reference.new(type: :at, name: scanner[8], first_column: start, last_column: scanner.pos)
            when scanner[9] # @[expr.right], @[expr-right]  (named reference with brackets)
              return Lrama::Grammar::Reference.new(type: :at, name: scanner[9], first_column: start, last_column: scanner.pos)

            # $: references
            when scanner[10] # $:$
              return Lrama::Grammar::Reference.new(type: :index, name: "$", first_column: start, last_column: scanner.pos)
            when scanner[11] # $:1
              return Lrama::Grammar::Reference.new(type: :index, number: Integer(scanner[11]), index: Integer(scanner[11]), first_column: start, last_column: scanner.pos)
            when scanner[12] # $:foo, $:expr (named reference without brackets)
              return Lrama::Grammar::Reference.new(type: :index, name: scanner[12], first_column: start, last_column: scanner.pos)
            when scanner[13] # $:[expr.right], $:[expr-right] (named reference with brackets)
              return Lrama::Grammar::Reference.new(type: :index, name: scanner[13], first_column: start, last_column: scanner.pos)
            end
          end
        end
      end
    end
  end
end
