# frozen_string_literal: true

require "forwardable"
require_relative "grammar/auxiliary"
require_relative "grammar/binding"
require_relative "grammar/code"
require_relative "grammar/counter"
require_relative "grammar/destructor"
require_relative "grammar/error_token"
require_relative "grammar/parameterizing_rule"
require_relative "grammar/percent_code"
require_relative "grammar/precedence"
require_relative "grammar/printer"
require_relative "grammar/reference"
require_relative "grammar/rule"
require_relative "grammar/rule_builder"
require_relative "grammar/symbol"
require_relative "grammar/symbols"
require_relative "grammar/type"
require_relative "grammar/union"
require_relative "lexer"

module Lrama
  # Grammar is the result of parsing an input grammar file
  class Grammar
    extend Forwardable

    attr_reader :percent_codes, :eof_symbol, :error_symbol, :undef_symbol, :accept_symbol, :aux, :parameterizing_rule_resolver
    attr_accessor :union, :expect, :printers, :error_tokens, :lex_param, :parse_param, :initial_action,
                  :after_shift, :before_reduce, :after_reduce, :after_shift_error_token, :after_pop_stack,
                  :symbols_resolver, :types, :rules, :rule_builders, :sym_to_rules, :no_stdlib, :locations

    def_delegators "@symbols_resolver", :symbols, :nterms, :terms, :add_nterm, :add_term, :find_term_by_s_value,
                                        :find_symbol_by_number!, :find_symbol_by_id!, :token_to_symbol,
                                        :find_symbol_by_s_value!, :fill_symbol_number, :fill_nterm_type,
                                        :fill_printer, :fill_destructor, :fill_error_token, :sort_by_number!

    def initialize(rule_counter)
      @rule_counter = rule_counter

      # Code defined by "%code"
      @percent_codes = []
      @printers = []
      @destructors = []
      @error_tokens = []
      @symbols_resolver = Grammar::Symbols::Resolver.new
      @types = []
      @rule_builders = []
      @rules = []
      @sym_to_rules = {}
      @parameterizing_rule_resolver = ParameterizingRule::Resolver.new
      @empty_symbol = nil
      @eof_symbol = nil
      @error_symbol = nil
      @undef_symbol = nil
      @accept_symbol = nil
      @aux = Auxiliary.new
      @no_stdlib = false
      @locations = false

      append_special_symbols
    end

    def create_rule_builder(rule_counter, midrule_action_counter)
      RuleBuilder.new(rule_counter, midrule_action_counter, @parameterizing_rule_resolver)
    end

    def add_percent_code(id:, code:)
      @percent_codes << PercentCode.new(id.s_value, code.s_value)
    end

    def add_destructor(ident_or_tags:, token_code:, lineno:)
      @destructors << Destructor.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
    end

    def add_printer(ident_or_tags:, token_code:, lineno:)
      @printers << Printer.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
    end

    def add_error_token(ident_or_tags:, token_code:, lineno:)
      @error_tokens << ErrorToken.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
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

    def add_parameterizing_rule(rule)
      @parameterizing_rule_resolver.add_parameterizing_rule(rule)
    end

    def parameterizing_rules
      @parameterizing_rule_resolver.rules
    end

    def insert_before_parameterizing_rules(rules)
      @parameterizing_rule_resolver.rules = rules + @parameterizing_rule_resolver.rules
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
      resolve_inline_rules
      normalize_rules
      collect_symbols
      set_lhs_and_rhs
      fill_default_precedence
      fill_symbols
      fill_sym_to_rules
      compute_nullable
      compute_first_set
      set_locations
    end

    # TODO: More validation methods
    #
    # * Validation for no_declared_type_reference
    def validate!
      @symbols_resolver.validate!
      validate_rule_lhs_is_nterm!
    end

    def find_rules_by_symbol!(sym)
      find_rules_by_symbol(sym) || (raise "Rules for #{sym} not found")
    end

    def find_rules_by_symbol(sym)
      @sym_to_rules[sym.number]
    end

    private

    def compute_nullable
      @rules.each do |rule|
        case
        when rule.empty_rule?
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

      nterms.select {|e| e.nullable.nil? }.each do |nterm|
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

    def resolve_inline_rules
      while @rule_builders.any? {|r| r.has_inline_rules? } do
        @rule_builders = @rule_builders.flat_map do |builder|
          if builder.has_inline_rules?
            builder.resolve_inline_rules
          else
            builder
          end
        end
      end
    end

    def normalize_rules
      # Add $accept rule to the top of rules
      rule_builder = @rule_builders.first # : RuleBuilder
      lineno = rule_builder ? rule_builder.line : 0
      @rules << Rule.new(id: @rule_counter.increment, _lhs: @accept_symbol.id, _rhs: [rule_builder.lhs, @eof_symbol.id], token_code: nil, lineno: lineno)

      setup_rules

      @rule_builders.each do |builder|
        builder.rules.each do |rule|
          add_nterm(id: rule._lhs, tag: rule.lhs_tag)
          @rules << rule
        end
      end

      @rules.sort_by!(&:id)
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

    def set_lhs_and_rhs
      @rules.each do |rule|
        rule.lhs = token_to_symbol(rule._lhs) if rule._lhs

        rule.rhs = rule._rhs.map do |t|
          token_to_symbol(t)
        end
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

    def fill_symbols
      fill_symbol_number
      fill_nterm_type(@types)
      fill_printer(@printers)
      fill_destructor(@destructors)
      fill_error_token(@error_tokens)
      sort_by_number!
    end

    def fill_sym_to_rules
      @rules.each do |rule|
        key = rule.lhs.number
        @sym_to_rules[key] ||= []
        @sym_to_rules[key] << rule
      end
    end

    def validate_rule_lhs_is_nterm!
      errors = [] #: Array[String]

      rules.each do |rule|
        next if rule.lhs.nterm?

        errors << "[BUG] LHS of #{rule.display_name} (line: #{rule.lineno}) is term. It should be nterm."
      end

      return if errors.empty?

      raise errors.join("\n")
    end

    def set_locations
      @locations = @locations || @rules.any? {|rule| rule.contains_at_reference? }
    end
  end
end
