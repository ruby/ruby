# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Symbols
      class Resolver
        # @rbs!
        #
        #   interface _DelegatedMethods
        #     def symbols: () -> Array[Grammar::Symbol]
        #     def nterms: () -> Array[Grammar::Symbol]
        #     def terms: () -> Array[Grammar::Symbol]
        #     def add_nterm: (id: Lexer::Token::Base, ?alias_name: String?, ?tag: Lexer::Token::Tag?) -> Grammar::Symbol
        #     def add_term: (id: Lexer::Token::Base, ?alias_name: String?, ?tag: Lexer::Token::Tag?, ?token_id: Integer?, ?replace: bool) -> Grammar::Symbol
        #     def find_symbol_by_number!: (Integer number) -> Grammar::Symbol
        #     def find_symbol_by_id!: (Lexer::Token::Base id) -> Grammar::Symbol
        #     def token_to_symbol: (Lexer::Token::Base token) -> Grammar::Symbol
        #     def find_symbol_by_s_value!: (::String s_value) -> Grammar::Symbol
        #     def fill_nterm_type: (Array[Grammar::Type] types) -> void
        #     def fill_symbol_number: () -> void
        #     def fill_printer: (Array[Grammar::Printer] printers) -> void
        #     def fill_destructor: (Array[Destructor] destructors) -> (Destructor | bot)
        #     def fill_error_token: (Array[Grammar::ErrorToken] error_tokens) -> void
        #     def sort_by_number!: () -> Array[Grammar::Symbol]
        #   end
        #
        #   @symbols: Array[Grammar::Symbol]?
        #   @number: Integer
        #   @used_numbers: Hash[Integer, bool]

        attr_reader :terms #: Array[Grammar::Symbol]
        attr_reader :nterms #: Array[Grammar::Symbol]

        # @rbs () -> void
        def initialize
          @terms = []
          @nterms = []
        end

        # @rbs () -> Array[Grammar::Symbol]
        def symbols
          @symbols ||= (@terms + @nterms)
        end

        # @rbs () -> Array[Grammar::Symbol]
        def sort_by_number!
          symbols.sort_by!(&:number)
        end

        # @rbs (id: Lexer::Token::Base, ?alias_name: String?, ?tag: Lexer::Token::Tag?, ?token_id: Integer?, ?replace: bool) -> Grammar::Symbol
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

        # @rbs (id: Lexer::Token::Base, ?alias_name: String?, ?tag: Lexer::Token::Tag?) -> Grammar::Symbol
        def add_nterm(id:, alias_name: nil, tag: nil)
          if (sym = find_symbol_by_id(id))
            return sym
          end

          @symbols = nil
          nterm = Symbol.new(
            id: id, alias_name: alias_name, number: nil, tag: tag,
            term: false, token_id: nil, nullable: nil,
          )
          @nterms << nterm
          nterm
        end

        # @rbs (::String s_value) -> Grammar::Symbol?
        def find_term_by_s_value(s_value)
          terms.find { |s| s.id.s_value == s_value }
        end

        # @rbs (::String s_value) -> Grammar::Symbol?
        def find_symbol_by_s_value(s_value)
          symbols.find { |s| s.id.s_value == s_value }
        end

        # @rbs (::String s_value) -> Grammar::Symbol
        def find_symbol_by_s_value!(s_value)
          find_symbol_by_s_value(s_value) || (raise "Symbol not found. value: `#{s_value}`")
        end

        # @rbs (Lexer::Token::Base id) -> Grammar::Symbol?
        def find_symbol_by_id(id)
          symbols.find do |s|
            s.id == id || s.alias_name == id.s_value
          end
        end

        # @rbs (Lexer::Token::Base id) -> Grammar::Symbol
        def find_symbol_by_id!(id)
          find_symbol_by_id(id) || (raise "Symbol not found. #{id}")
        end

        # @rbs (Integer token_id) -> Grammar::Symbol?
        def find_symbol_by_token_id(token_id)
          symbols.find {|s| s.token_id == token_id }
        end

        # @rbs (Integer number) -> Grammar::Symbol
        def find_symbol_by_number!(number)
          sym = symbols[number]

          raise "Symbol not found. number: `#{number}`" unless sym
          raise "[BUG] Symbol number mismatch. #{number}, #{sym}" if sym.number != number

          sym
        end

        # @rbs () -> void
        def fill_symbol_number
          # YYEMPTY = -2
          # YYEOF   =  0
          # YYerror =  1
          # YYUNDEF =  2
          @number = 3
          fill_terms_number
          fill_nterms_number
        end

        # @rbs (Array[Grammar::Type] types) -> void
        def fill_nterm_type(types)
          types.each do |type|
            nterm = find_nterm_by_id!(type.id)
            nterm.tag = type.tag
          end
        end

        # @rbs (Array[Grammar::Printer] printers) -> void
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

        # @rbs (Array[Destructor] destructors) -> (Array[Grammar::Symbol] | bot)
        def fill_destructor(destructors)
          symbols.each do |sym|
            destructors.each do |destructor|
              destructor.ident_or_tags.each do |ident_or_tag|
                case ident_or_tag
                when Lrama::Lexer::Token::Ident
                  sym.destructor = destructor if sym.id == ident_or_tag
                when Lrama::Lexer::Token::Tag
                  sym.destructor = destructor if sym.tag == ident_or_tag
                else
                  raise "Unknown token type. #{destructor}"
                end
              end
            end
          end
        end

        # @rbs (Array[Grammar::ErrorToken] error_tokens) -> void
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

        # @rbs (Lexer::Token::Base token) -> Grammar::Symbol
        def token_to_symbol(token)
          case token
          when Lrama::Lexer::Token::Base
            find_symbol_by_id!(token)
          else
            raise "Unknown class: #{token}"
          end
        end

        # @rbs () -> void
        def validate!
          validate_number_uniqueness!
          validate_alias_name_uniqueness!
          validate_symbols!
        end

        private

        # @rbs (Lexer::Token::Base id) -> Grammar::Symbol
        def find_nterm_by_id!(id)
          @nterms.find do |s|
            s.id == id
          end || (raise "Symbol not found. #{id}")
        end

        # @rbs () -> void
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

        # @rbs () -> void
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

        # @rbs () -> Hash[Integer, bool]
        def used_numbers
          return @used_numbers if defined?(@used_numbers)

          @used_numbers = {}
          symbols.map(&:number).each do |n|
            @used_numbers[n] = true
          end
          @used_numbers
        end

        # @rbs () -> void
        def validate_number_uniqueness!
          invalid = symbols.group_by(&:number).select do |number, syms|
            syms.count > 1
          end

          return if invalid.empty?

          raise "Symbol number is duplicated. #{invalid}"
        end

        # @rbs () -> void
        def validate_alias_name_uniqueness!
          invalid = symbols.select(&:alias_name).group_by(&:alias_name).select do |alias_name, syms|
            syms.count > 1
          end

          return if invalid.empty?

          raise "Symbol alias name is duplicated. #{invalid}"
        end

        # @rbs () -> void
        def validate_symbols!
          symbols.each { |sym| sym.id.validate }
          errors = symbols.map { |sym| sym.id.errors }.flatten.compact
          return if errors.empty?

          raise errors.join("\n")
        end
      end
    end
  end
end
