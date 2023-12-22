require "lrama/grammar/auxiliary"
require "lrama/grammar/code"
require "lrama/grammar/counter"
require "lrama/grammar/error_token"
require "lrama/grammar/percent_code"
require "lrama/grammar/precedence"
require "lrama/grammar/printer"
require "lrama/grammar/reference"
require "lrama/grammar/rule"
require "lrama/grammar/rule_builder"
require "lrama/grammar/symbol"
require "lrama/grammar/type"
require "lrama/grammar/union"
require "lrama/lexer"

module Lrama
  # Grammar is the result of parsing an input grammar file
  class Grammar
    attr_reader :percent_codes, :eof_symbol, :error_symbol, :undef_symbol, :accept_symbol, :aux
    attr_accessor :union, :expect,
                  :printers, :error_tokens,
                  :lex_param, :parse_param, :initial_action,
                  :symbols, :types,
                  :rules, :rule_builders,
                  :sym_to_rules

    def initialize(rule_counter)
      @rule_counter = rule_counter

      # Code defined by "%code"
      @percent_codes = []
      @printers = []
      @error_tokens = []
      @symbols = []
      @types = []
      @rule_builders = []
      @rules = []
      @sym_to_rules = {}
      @empty_symbol = nil
      @eof_symbol = nil
      @error_symbol = nil
      @undef_symbol = nil
      @accept_symbol = nil
      @aux = Auxiliary.new

      append_special_symbols
    end

    def add_percent_code(id:, code:)
      @percent_codes << PercentCode.new(id, code)
    end

    def add_printer(ident_or_tags:, token_code:, lineno:)
      @printers << Printer.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
    end

    def add_error_token(ident_or_tags:, token_code:, lineno:)
      @error_tokens << ErrorToken.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
    end

    def add_term(id:, alias_name: nil, tag: nil, token_id: nil, replace: false)
      if token_id && (sym = @symbols.find {|s| s.token_id == token_id })
        if replace
          sym.id = id
          sym.alias_name = alias_name
          sym.tag = tag
        end

        return sym
      end

      if sym = @symbols.find {|s| s.id == id }
        return sym
      end

      sym = Symbol.new(
        id: id, alias_name: alias_name, number: nil, tag: tag,
        term: true, token_id: token_id, nullable: false
      )
      @symbols << sym
      @terms = nil

      return sym
    end

    def add_nterm(id:, alias_name: nil, tag: nil)
      return if @symbols.find {|s| s.id == id }

      sym = Symbol.new(
        id: id, alias_name: alias_name, number: nil, tag: tag,
        term: false, token_id: nil, nullable: nil,
      )
      @symbols << sym
      @nterms = nil

      return sym
    end

    def add_type(id:, tag:)
      @types << Type.new(id: id, tag: tag)
    end

    def add_nonassoc(sym, precedence)
      set_precedence(sym, Precedence.new(type: :nonassoc, precedence: precedence))
    end

    def add_left(sym, precedence)
      set_precedence(sym, Precedence.new(type: :left, precedence: precedence))
    end

    def add_right(sym, precedence)
      set_precedence(sym, Precedence.new(type: :right, precedence: precedence))
    end

    def add_precedence(sym, precedence)
      set_precedence(sym, Precedence.new(type: :precedence, precedence: precedence))
    end

    def set_precedence(sym, precedence)
      raise "" if sym.nterm?
      sym.precedence = precedence
    end

    def set_union(code, lineno)
      @union = Union.new(code: code, lineno: lineno)
    end

    def add_rule_builder(builder)
      @rule_builders << builder
    end

    def prologue_first_lineno=(prologue_first_lineno)
      @aux.prologue_first_lineno = prologue_first_lineno
    end

    def prologue=(prologue)
      @aux.prologue = prologue
    end

    def epilogue_first_lineno=(epilogue_first_lineno)
      @aux.epilogue_first_lineno = epilogue_first_lineno
    end

    def epilogue=(epilogue)
      @aux.epilogue = epilogue
    end

    def prepare
      normalize_rules
      collect_symbols
      set_lhs_and_rhs
      fill_symbol_number
      fill_default_precedence
      fill_sym_to_rules
      fill_nterm_type
      fill_symbol_printer
      fill_symbol_error_token
      @symbols.sort_by!(&:number)
      compute_nullable
      compute_first_set
    end

    # TODO: More validation methods
    #
    # * Validaiton for no_declared_type_reference
    def validate!
      validate_symbol_number_uniqueness!
      validate_symbol_alias_name_uniqueness!
      validate_rule_lhs_is_nterm!
    end

    def find_symbol_by_s_value(s_value)
      @symbols.find do |sym|
        sym.id.s_value == s_value
      end
    end

    def find_symbol_by_s_value!(s_value)
      find_symbol_by_s_value(s_value) || (raise "Symbol not found: #{s_value}")
    end

    def find_symbol_by_id(id)
      @symbols.find do |sym|
        sym.id == id || sym.alias_name == id.s_value
      end
    end

    def find_symbol_by_id!(id)
      find_symbol_by_id(id) || (raise "Symbol not found: #{id}")
    end

    def find_symbol_by_number!(number)
      sym = @symbols[number]

      raise "Symbol not found: #{number}" unless sym
      raise "[BUG] Symbol number mismatch. #{number}, #{sym}" if sym.number != number

      sym
    end

    def find_rules_by_symbol!(sym)
      find_rules_by_symbol(sym) || (raise "Rules for #{sym} not found")
    end

    def find_rules_by_symbol(sym)
      @sym_to_rules[sym.number]
    end

    def terms_count
      terms.count
    end

    def terms
      @terms ||= @symbols.select(&:term?)
    end

    def nterms_count
      nterms.count
    end

    def nterms
      @nterms ||= @symbols.select(&:nterm?)
    end

    private

    def compute_nullable
      @rules.each do |rule|
        case
        when rule.rhs.empty?
          rule.nullable = true
        when rule.rhs.any?(&:term)
          rule.nullable = false
        else
          # noop
        end
      end

      while true do
        rs  = @rules.select {|e| e.nullable.nil? }
        nts = nterms.select {|e| e.nullable.nil? }
        rule_count_1  = rs.count
        nterm_count_1 = nts.count

        rs.each do |rule|
          if rule.rhs.all?(&:nullable)
            rule.nullable = true
          end
        end

        nts.each do |nterm|
          find_rules_by_symbol!(nterm).each do |rule|
            if rule.nullable
              nterm.nullable = true
            end
          end
        end

        rule_count_2  = @rules.count {|e| e.nullable.nil? }
        nterm_count_2 = nterms.count {|e| e.nullable.nil? }

        if (rule_count_1 == rule_count_2) && (nterm_count_1 == nterm_count_2)
          break
        end
      end

      rules.select {|r| r.nullable.nil? }.each do |rule|
        rule.nullable = false
      end

      nterms.select {|r| r.nullable.nil? }.each do |nterm|
        nterm.nullable = false
      end
    end

    def compute_first_set
      terms.each do |term|
        term.first_set = Set.new([term]).freeze
        term.first_set_bitmap = Lrama::Bitmap.from_array([term.number])
      end

      nterms.each do |nterm|
        nterm.first_set = Set.new([]).freeze
        nterm.first_set_bitmap = Lrama::Bitmap.from_array([])
      end

      while true do
        changed = false

        @rules.each do |rule|
          rule.rhs.each do |r|
            if rule.lhs.first_set_bitmap | r.first_set_bitmap != rule.lhs.first_set_bitmap
              changed = true
              rule.lhs.first_set_bitmap = rule.lhs.first_set_bitmap | r.first_set_bitmap
            end

            break unless r.nullable
          end
        end

        break unless changed
      end

      nterms.each do |nterm|
        nterm.first_set = Lrama::Bitmap.to_array(nterm.first_set_bitmap).map do |number|
          find_symbol_by_number!(number)
        end.to_set
      end
    end

    def setup_rules
      @rule_builders.each do |builder|
        builder.setup_rules
      end
    end

    def find_nterm_by_id!(id)
      nterms.find do |nterm|
        nterm.id == id
      end || (raise "Nterm not found: #{id}")
    end

    def append_special_symbols
      # YYEMPTY (token_id: -2, number: -2) is added when a template is evaluated
      # term = add_term(id: Token.new(Token::Ident, "YYEMPTY"), token_id: -2)
      # term.number = -2
      # @empty_symbol = term

      # YYEOF
      term = add_term(id: Lrama::Lexer::Token::Ident.new(s_value: "YYEOF"), alias_name: "\"end of file\"", token_id: 0)
      term.number = 0
      term.eof_symbol = true
      @eof_symbol = term

      # YYerror
      term = add_term(id: Lrama::Lexer::Token::Ident.new(s_value: "YYerror"), alias_name: "error")
      term.number = 1
      term.error_symbol = true
      @error_symbol = term

      # YYUNDEF
      term = add_term(id: Lrama::Lexer::Token::Ident.new(s_value: "YYUNDEF"), alias_name: "\"invalid token\"")
      term.number = 2
      term.undef_symbol = true
      @undef_symbol = term

      # $accept
      term = add_nterm(id: Lrama::Lexer::Token::Ident.new(s_value: "$accept"))
      term.accept_symbol = true
      @accept_symbol = term
    end

    # 1. Add $accept rule to the top of rules
    # 2. Extract action in the middle of RHS into new Empty rule
    # 3. Append id and extract action then create Rule
    #
    # Bison 3.8.2 uses different orders for symbol number and rule number
    # when a rule has actions in the middle of a rule.
    #
    # For example,
    #
    # `program: $@1 top_compstmt`
    #
    # Rules are ordered like below,
    #
    # 1 $@1: ε
    # 2 program: $@1 top_compstmt
    #
    # Symbols are ordered like below,
    #
    # 164 program
    # 165 $@1
    #
    def normalize_rules
      # 1. Add $accept rule to the top of rules
      accept = @accept_symbol
      eof = @eof_symbol
      lineno = @rule_builders.first ? @rule_builders.first.line : 0
      @rules << Rule.new(id: @rule_counter.increment, _lhs: accept.id, _rhs: [@rule_builders.first.lhs, eof.id], token_code: nil, lineno: lineno)

      setup_rules

      @rule_builders.each do |builder|
        # Extract actions in the middle of RHS into new rules.
        builder.midrule_action_rules.each do |rule|
          @rules << rule
        end

        builder.rules.each do |rule|
          add_nterm(id: rule._lhs)
          @rules << rule
        end

        builder.parameterizing_rules.each do |rule|
          add_nterm(id: rule._lhs, tag: rule.lhs_tag)
          @rules << rule
        end

        builder.midrule_action_rules.each do |rule|
          add_nterm(id: rule._lhs)
        end
      end
    end

    # Collect symbols from rules
    def collect_symbols
      @rules.flat_map(&:_rhs).each do |s|
        case s
        when Lrama::Lexer::Token::Char
          add_term(id: s)
        when Lrama::Lexer::Token
          # skip
        else
          raise "Unknown class: #{s}"
        end
      end
    end

    # Fill #number and #token_id
    def fill_symbol_number
      # Character literal in grammar file has
      # token id corresponding to ASCII code by default,
      # so start token_id from 256.
      token_id = 256

      # YYEMPTY = -2
      # YYEOF   =  0
      # YYerror =  1
      # YYUNDEF =  2
      number = 3

      nterm_token_id = 0
      used_numbers = {}

      @symbols.map(&:number).each do |n|
        used_numbers[n] = true
      end

      (@symbols.select(&:term?) + @symbols.select(&:nterm?)).each do |sym|
        while used_numbers[number] do
          number += 1
        end

        if sym.number.nil?
          sym.number = number
          number += 1
        end

        # If id is Token::Char, it uses ASCII code
        if sym.term? && sym.token_id.nil?
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
              sym.token_id = Integer($1, 8)
            when /\A(.)\z/
              sym.token_id = $1.bytes.first
            else
              raise "Unknown Char s_value #{sym}"
            end
          else
            sym.token_id = token_id
            token_id += 1
          end
        end

        if sym.nterm? && sym.token_id.nil?
          sym.token_id = nterm_token_id
          nterm_token_id += 1
        end
      end
    end

    def set_lhs_and_rhs
      @rules.each do |rule|
        rule.lhs = token_to_symbol(rule._lhs) if rule._lhs

        rule.rhs = rule._rhs.map do |t|
          token_to_symbol(t)
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

    # Rule inherits precedence from the last term in RHS.
    #
    # https://www.gnu.org/software/bison/manual/html_node/How-Precedence.html
    def fill_default_precedence
      @rules.each do |rule|
        # Explicitly specified precedence has the highest priority
        next if rule.precedence_sym

        precedence_sym = nil
        rule.rhs.each do |sym|
          precedence_sym = sym if sym.term?
        end

        rule.precedence_sym = precedence_sym
      end
    end

    def fill_sym_to_rules
      @rules.each do |rule|
        key = rule.lhs.number
        @sym_to_rules[key] ||= []
        @sym_to_rules[key] << rule
      end
    end

    # Fill nterm's tag defined by %type decl
    def fill_nterm_type
      @types.each do |type|
        nterm = find_nterm_by_id!(type.id)
        nterm.tag = type.tag
      end
    end

    def fill_symbol_printer
      @symbols.each do |sym|
        @printers.each do |printer|
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

    def fill_symbol_error_token
      @symbols.each do |sym|
        @error_tokens.each do |error_token|
          error_token.ident_or_tags.each do |ident_or_tag|
            case ident_or_tag
            when Lrama::Lexer::Token::Ident
              sym.error_token = error_token if sym.id == ident_or_tag
            when Lrama::Lexer::Token::Tag
              sym.error_token = error_token if sym.tag == ident_or_tag
            else
              raise "Unknown token type. #{error_token}"
            end
          end
        end
      end
    end

    def validate_symbol_number_uniqueness!
      invalid = @symbols.group_by(&:number).select do |number, syms|
        syms.count > 1
      end

      return if invalid.empty?

      raise "Symbol number is duplicated. #{invalid}"
    end

    def validate_symbol_alias_name_uniqueness!
      invalid = @symbols.select(&:alias_name).group_by(&:alias_name).select do |alias_name, syms|
        syms.count > 1
      end

      return if invalid.empty?

      raise "Symbol alias name is duplicated. #{invalid}"
    end

    def validate_rule_lhs_is_nterm!
      errors = []

      rules.each do |rule|
        next if rule.lhs.nterm?

        errors << "[BUG] LHS of #{rule} (line: #{rule.lineno}) is term. It should be nterm."
      end

      return if errors.empty?

      raise errors.join("\n")
    end
  end
end
