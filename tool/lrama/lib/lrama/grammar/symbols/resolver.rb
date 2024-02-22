module Lrama
  class Grammar
    class Symbols
      class Resolver
        attr_reader :terms, :nterms

        def initialize
          @terms = []
          @nterms = []
        end

        def symbols
          @symbols ||= (@terms + @nterms)
        end

        def sort_by_number!
          symbols.sort_by!(&:number)
        end

        def add_term(id:, alias_name: nil, tag: nil, token_id: nil, replace: false)
          if token_id && (sym = find_symbol_by_token_id(token_id))
            if replace
              sym.id = id
              sym.alias_name = alias_name
              sym.tag = tag
            end

            return sym
          end

          if (sym = find_symbol_by_id(id))
            return sym
          end

          @symbols = nil
          term = Symbol.new(
            id: id, alias_name: alias_name, number: nil, tag: tag,
            term: true, token_id: token_id, nullable: false
          )
          @terms << term
          term
        end

        def add_nterm(id:, alias_name: nil, tag: nil)
          return if find_symbol_by_id(id)

          @symbols = nil
          nterm = Symbol.new(
            id: id, alias_name: alias_name, number: nil, tag: tag,
            term: false, token_id: nil, nullable: nil,
          )
          @nterms << nterm
          nterm
        end

        def find_symbol_by_s_value(s_value)
          symbols.find { |s| s.id.s_value == s_value }
        end

        def find_symbol_by_s_value!(s_value)
          find_symbol_by_s_value(s_value) || (raise "Symbol not found: #{s_value}")
        end

        def find_symbol_by_id(id)
          symbols.find do |s|
            s.id == id || s.alias_name == id.s_value
          end
        end

        def find_symbol_by_id!(id)
          find_symbol_by_id(id) || (raise "Symbol not found: #{id}")
        end

        def find_symbol_by_token_id(token_id)
          symbols.find {|s| s.token_id == token_id }
        end

        def find_symbol_by_number!(number)
          sym = symbols[number]

          raise "Symbol not found: #{number}" unless sym
          raise "[BUG] Symbol number mismatch. #{number}, #{sym}" if sym.number != number

          sym
        end

        def fill_symbol_number
          # YYEMPTY = -2
          # YYEOF   =  0
          # YYerror =  1
          # YYUNDEF =  2
          @number = 3
          fill_terms_number
          fill_nterms_number
        end

        def fill_nterm_type(types)
          types.each do |type|
            nterm = find_nterm_by_id!(type.id)
            nterm.tag = type.tag
          end
        end

        def fill_printer(printers)
          symbols.each do |sym|
            printers.each do |printer|
              printer.ident_or_tags.each do |ident_or_tag|
                case ident_or_tag
                when Lrama::Lexer::Token::Ident
                  sym.printer = printer if sym.id == ident_or_tag
                when Lrama::Lexer::Token::Tag
                  sym.printer = printer if sym.tag == ident_or_tag
                else
                  raise "Unknown token type. #{printer}"
                end
              end
            end
          end
        end

        def fill_error_token(error_tokens)
          symbols.each do |sym|
            error_tokens.each do |token|
              token.ident_or_tags.each do |ident_or_tag|
                case ident_or_tag
                when Lrama::Lexer::Token::Ident
                  sym.error_token = token if sym.id == ident_or_tag
                when Lrama::Lexer::Token::Tag
                  sym.error_token = token if sym.tag == ident_or_tag
                else
                  raise "Unknown token type. #{token}"
                end
              end
            end
          end
        end

        def token_to_symbol(token)
          case token
          when Lrama::Lexer::Token
            find_symbol_by_id!(token)
          else
            raise "Unknown class: #{token}"
          end
        end

        def validate!
          validate_number_uniqueness!
          validate_alias_name_uniqueness!
        end

        private

        def find_nterm_by_id!(id)
          @nterms.find do |s|
            s.id == id
          end || (raise "Symbol not found: #{id}")
        end

        def fill_terms_number
          # Character literal in grammar file has
          # token id corresponding to ASCII code by default,
          # so start token_id from 256.
          token_id = 256

          @terms.each do |sym|
            while used_numbers[@number] do
              @number += 1
            end

            if sym.number.nil?
              sym.number = @number
              used_numbers[@number] = true
              @number += 1
            end

            # If id is Token::Char, it uses ASCII code
            if sym.token_id.nil?
              if sym.id.is_a?(Lrama::Lexer::Token::Char)
                # Ignore ' on the both sides
                case sym.id.s_value[1..-2]
                when "\\b"
                  sym.token_id = 8
                when "\\f"
                  sym.token_id = 12
                when "\\n"
                  sym.token_id = 10
                when "\\r"
                  sym.token_id = 13
                when "\\t"
                  sym.token_id = 9
                when "\\v"
                  sym.token_id = 11
                when "\""
                  sym.token_id = 34
                when "'"
                  sym.token_id = 39
                when "\\\\"
                  sym.token_id = 92
                when /\A\\(\d+)\z/
                  unless (id = Integer($1, 8)).nil?
                    sym.token_id = id
                  else
                    raise "Unknown Char s_value #{sym}"
                  end
                when /\A(.)\z/
                  unless (id = $1&.bytes&.first).nil?
                    sym.token_id = id
                  else
                    raise "Unknown Char s_value #{sym}"
                  end
                else
                  raise "Unknown Char s_value #{sym}"
                end
              else
                sym.token_id = token_id
                token_id += 1
              end
            end
          end
        end

        def fill_nterms_number
          token_id = 0

          @nterms.each do |sym|
            while used_numbers[@number] do
              @number += 1
            end

            if sym.number.nil?
              sym.number = @number
              used_numbers[@number] = true
              @number += 1
            end

            if sym.token_id.nil?
              sym.token_id = token_id
              token_id += 1
            end
          end
        end

        def used_numbers
          return @used_numbers if defined?(@used_numbers)

          @used_numbers = {}
          symbols.map(&:number).each do |n|
            @used_numbers[n] = true
          end
          @used_numbers
        end

        def validate_number_uniqueness!
          invalid = symbols.group_by(&:number).select do |number, syms|
            syms.count > 1
          end

          return if invalid.empty?

          raise "Symbol number is duplicated. #{invalid}"
        end

        def validate_alias_name_uniqueness!
          invalid = symbols.select(&:alias_name).group_by(&:alias_name).select do |alias_name, syms|
            syms.count > 1
          end

          return if invalid.empty?

          raise "Symbol alias name is duplicated. #{invalid}"
        end
      end
    end
  end
end
