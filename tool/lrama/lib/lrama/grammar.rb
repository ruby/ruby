# rbs_inline: enabled
# frozen_string_literal: true

require "forwardable"
require_relative "grammar/auxiliary"
require_relative "grammar/binding"
require_relative "grammar/code"
require_relative "grammar/counter"
require_relative "grammar/destructor"
require_relative "grammar/error_token"
require_relative "grammar/inline"
require_relative "grammar/parameterized"
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
    # @rbs!
    #
    #   interface _DelegatedMethods
    #     def rules: () -> Array[Rule]
    #     def accept_symbol: () -> Grammar::Symbol
    #     def eof_symbol: () -> Grammar::Symbol
    #     def undef_symbol: () -> Grammar::Symbol
    #     def precedences: () -> Array[Precedence]
    #
    #     # delegate to @symbols_resolver
    #     def symbols: () -> Array[Grammar::Symbol]
    #     def terms: () -> Array[Grammar::Symbol]
    #     def nterms: () -> Array[Grammar::Symbol]
    #     def find_symbol_by_s_value!: (::String s_value) -> Grammar::Symbol
    #     def ielr_defined?: () -> bool
    #   end
    #
    #   include Symbols::Resolver::_DelegatedMethods
    #
    #   @rule_counter: Counter
    #   @percent_codes: Array[PercentCode]
    #   @printers: Array[Printer]
    #   @destructors: Array[Destructor]
    #   @error_tokens: Array[ErrorToken]
    #   @symbols_resolver: Symbols::Resolver
    #   @types: Array[Type]
    #   @rule_builders: Array[RuleBuilder]
    #   @rules: Array[Rule]
    #   @sym_to_rules: Hash[Integer, Array[Rule]]
    #   @parameterized_resolver: Parameterized::Resolver
    #   @empty_symbol: Grammar::Symbol
    #   @eof_symbol: Grammar::Symbol
    #   @error_symbol: Grammar::Symbol
    #   @undef_symbol: Grammar::Symbol
    #   @accept_symbol: Grammar::Symbol
    #   @aux: Auxiliary
    #   @no_stdlib: bool
    #   @locations: bool
    #   @define: Hash[String, String]
    #   @required: bool
    #   @union: Union
    #   @precedences: Array[Precedence]
    #   @start_nterm: Lrama::Lexer::Token::Base?

    extend Forwardable

    attr_reader :percent_codes #: Array[PercentCode]
    attr_reader :eof_symbol #: Grammar::Symbol
    attr_reader :error_symbol #: Grammar::Symbol
    attr_reader :undef_symbol #: Grammar::Symbol
    attr_reader :accept_symbol #: Grammar::Symbol
    attr_reader :aux #: Auxiliary
    attr_reader :parameterized_resolver #: Parameterized::Resolver
    attr_reader :precedences #: Array[Precedence]
    attr_accessor :union #: Union
    attr_accessor :expect #: Integer
    attr_accessor :printers #: Array[Printer]
    attr_accessor :error_tokens #: Array[ErrorToken]
    attr_accessor :lex_param #: String
    attr_accessor :parse_param #: String
    attr_accessor :initial_action #: Grammar::Code::InitialActionCode
    attr_accessor :after_shift #: Lexer::Token::Base
    attr_accessor :before_reduce #: Lexer::Token::Base
    attr_accessor :after_reduce #: Lexer::Token::Base
    attr_accessor :after_shift_error_token #: Lexer::Token::Base
    attr_accessor :after_pop_stack #: Lexer::Token::Base
    attr_accessor :symbols_resolver #: Symbols::Resolver
    attr_accessor :types #: Array[Type]
    attr_accessor :rules #: Array[Rule]
    attr_accessor :rule_builders #: Array[RuleBuilder]
    attr_accessor :sym_to_rules #: Hash[Integer, Array[Rule]]
    attr_accessor :no_stdlib #: bool
    attr_accessor :locations #: bool
    attr_accessor :define #: Hash[String, String]
    attr_accessor :required #: bool

    def_delegators "@symbols_resolver", :symbols, :nterms, :terms, :add_nterm, :add_term, :find_term_by_s_value,
                                        :find_symbol_by_number!, :find_symbol_by_id!, :token_to_symbol,
                                        :find_symbol_by_s_value!, :fill_symbol_number, :fill_nterm_type,
                                        :fill_printer, :fill_destructor, :fill_error_token, :sort_by_number!

    # @rbs (Counter rule_counter, bool locations, Hash[String, String] define) -> void
    def initialize(rule_counter, locations, define = {})
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
      @parameterized_resolver = Parameterized::Resolver.new
      @empty_symbol = nil
      @eof_symbol = nil
      @error_symbol = nil
      @undef_symbol = nil
      @accept_symbol = nil
      @aux = Auxiliary.new
      @no_stdlib = false
      @locations = locations
      @define = define
      @required = false
      @precedences = []
      @start_nterm = nil

      append_special_symbols
    end

    # @rbs (Counter rule_counter, Counter midrule_action_counter) -> RuleBuilder
    def create_rule_builder(rule_counter, midrule_action_counter)
      RuleBuilder.new(rule_counter, midrule_action_counter, @parameterized_resolver)
    end

    # @rbs (id: Lexer::Token::Base, code: Lexer::Token::UserCode) -> Array[PercentCode]
    def add_percent_code(id:, code:)
      @percent_codes << PercentCode.new(id.s_value, code.s_value)
    end

    # @rbs (ident_or_tags: Array[Lexer::Token::Ident|Lexer::Token::Tag], token_code: Lexer::Token::UserCode, lineno: Integer) -> Array[Destructor]
    def add_destructor(ident_or_tags:, token_code:, lineno:)
      @destructors << Destructor.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
    end

    # @rbs (ident_or_tags: Array[Lexer::Token::Ident|Lexer::Token::Tag], token_code: Lexer::Token::UserCode, lineno: Integer) -> Array[Printer]
    def add_printer(ident_or_tags:, token_code:, lineno:)
      @printers << Printer.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
    end

    # @rbs (ident_or_tags: Array[Lexer::Token::Ident|Lexer::Token::Tag], token_code: Lexer::Token::UserCode, lineno: Integer) -> Array[ErrorToken]
    def add_error_token(ident_or_tags:, token_code:, lineno:)
      @error_tokens << ErrorToken.new(ident_or_tags: ident_or_tags, token_code: token_code, lineno: lineno)
    end

    # @rbs (id: Lexer::Token::Base, tag: Lexer::Token::Tag) -> Array[Type]
    def add_type(id:, tag:)
      @types << Type.new(id: id, tag: tag)
    end

    # @rbs (Grammar::Symbol sym, Integer precedence, String s_value, Integer lineno) -> Precedence
    def add_nonassoc(sym, precedence, s_value, lineno)
      set_precedence(sym, Precedence.new(symbol: sym, s_value: s_value, type: :nonassoc, precedence: precedence, lineno: lineno))
    end

    # @rbs (Grammar::Symbol sym, Integer precedence, String s_value, Integer lineno) -> Precedence
    def add_left(sym, precedence, s_value, lineno)
      set_precedence(sym, Precedence.new(symbol: sym, s_value: s_value, type: :left, precedence: precedence, lineno: lineno))
    end

    # @rbs (Grammar::Symbol sym, Integer precedence, String s_value, Integer lineno) -> Precedence
    def add_right(sym, precedence, s_value, lineno)
      set_precedence(sym, Precedence.new(symbol: sym, s_value: s_value, type: :right, precedence: precedence, lineno: lineno))
    end

    # @rbs (Grammar::Symbol sym, Integer precedence, String s_value, Integer lineno) -> Precedence
    def add_precedence(sym, precedence, s_value, lineno)
      set_precedence(sym, Precedence.new(symbol: sym, s_value: s_value, type: :precedence, precedence: precedence, lineno: lineno))
    end

    # @rbs (Lrama::Lexer::Token::Base id) -> Lrama::Lexer::Token::Base
    def set_start_nterm(id)
      # When multiple `%start` directives are defined, Bison does not generate an error,
      # whereas Lrama does generate an error.
      # Related Bison's specification are
      #   refs: https://www.gnu.org/software/bison/manual/html_node/Multiple-start_002dsymbols.html
      if @start_nterm.nil?
        @start_nterm = id
      else
        start = @start_nterm #: Lrama::Lexer::Token::Base
        raise "Start non-terminal is already set to #{start.s_value} (line: #{start.first_line}). Cannot set to #{id.s_value} (line: #{id.first_line})."
      end
    end

    # @rbs (Grammar::Symbol sym, Precedence precedence) -> (Precedence | bot)
    def set_precedence(sym, precedence)
      @precedences << precedence
      sym.precedence = precedence
    end

    # @rbs (Grammar::Code::NoReferenceCode code, Integer lineno) -> Union
    def set_union(code, lineno)
      @union = Union.new(code: code, lineno: lineno)
    end

    # @rbs (RuleBuilder builder) -> Array[RuleBuilder]
    def add_rule_builder(builder)
      @rule_builders << builder
    end

    # @rbs (Parameterized::Rule rule) -> Array[Parameterized::Rule]
    def add_parameterized_rule(rule)
      @parameterized_resolver.add_rule(rule)
    end

    # @rbs () -> Array[Parameterized::Rule]
    def parameterized_rules
      @parameterized_resolver.rules
    end

    # @rbs (Array[Parameterized::Rule] rules) -> Array[Parameterized::Rule]
    def prepend_parameterized_rules(rules)
      @parameterized_resolver.rules = rules + @parameterized_resolver.rules
    end

    # @rbs (Integer prologue_first_lineno) -> Integer
    def prologue_first_lineno=(prologue_first_lineno)
      @aux.prologue_first_lineno = prologue_first_lineno
    end

    # @rbs (String prologue) -> String
    def prologue=(prologue)
      @aux.prologue = prologue
    end

    # @rbs (Integer epilogue_first_lineno) -> Integer
    def epilogue_first_lineno=(epilogue_first_lineno)
      @aux.epilogue_first_lineno = epilogue_first_lineno
    end

    # @rbs (String epilogue) -> String
    def epilogue=(epilogue)
      @aux.epilogue = epilogue
    end

    # @rbs () -> void
    def prepare
      resolve_inline_rules
      normalize_rules
      collect_symbols
      set_lhs_and_rhs
      fill_default_precedence
      fill_symbols
      fill_sym_to_rules
      sort_precedence
      compute_nullable
      compute_first_set
      set_locations
    end

    # TODO: More validation methods
    #
    # * Validation for no_declared_type_reference
    #
    # @rbs () -> void
    def validate!
      @symbols_resolver.validate!
      validate_no_precedence_for_nterm!
      validate_rule_lhs_is_nterm!
      validate_duplicated_precedence!
    end

    # @rbs (Grammar::Symbol sym) -> Array[Rule]
    def find_rules_by_symbol!(sym)
      find_rules_by_symbol(sym) || (raise "Rules for #{sym} not found")
    end

    # @rbs (Grammar::Symbol sym) -> Array[Rule]?
    def find_rules_by_symbol(sym)
      @sym_to_rules[sym.number]
    end

    # @rbs (String s_value) -> Array[Rule]
    def select_rules_by_s_value(s_value)
      @rules.select {|rule| rule.lhs.id.s_value == s_value }
    end

    # @rbs () -> Array[String]
    def unique_rule_s_values
      @rules.map {|rule| rule.lhs.id.s_value }.uniq
    end

    # @rbs () -> bool
    def ielr_defined?
      @define.key?('lr.type') && @define['lr.type'] == 'ielr'
    end

    private

    # @rbs () -> void
    def sort_precedence
      @precedences.sort_by! do |prec|
        prec.symbol.number
      end
      @precedences.freeze
    end

    # @rbs () -> Array[Grammar::Symbol]
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

    # @rbs () -> Array[Grammar::Symbol]
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

    # @rbs () -> Array[RuleBuilder]
    def setup_rules
      @rule_builders.each do |builder|
        builder.setup_rules
      end
    end

    # @rbs () -> Grammar::Symbol
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

    # @rbs () -> void
    def resolve_inline_rules
      while @rule_builders.any?(&:has_inline_rules?) do
        @rule_builders = @rule_builders.flat_map do |builder|
          if builder.has_inline_rules?
            Inline::Resolver.new(builder).resolve
          else
            builder
          end
        end
      end
    end

    # @rbs () -> void
    def normalize_rules
      add_accept_rule
      setup_rules
      @rule_builders.each do |builder|
        builder.rules.each do |rule|
          add_nterm(id: rule._lhs, tag: rule.lhs_tag)
          @rules << rule
        end
      end

      nterms.freeze
      @rules.sort_by!(&:id).freeze
    end

    # Add $accept rule to the top of rules
    def add_accept_rule
      if @start_nterm
        start = @start_nterm #: Lrama::Lexer::Token::Base
        @rules << Rule.new(id: @rule_counter.increment, _lhs: @accept_symbol.id, _rhs: [start, @eof_symbol.id], token_code: nil, lineno: start.line)
      else
        rule_builder = @rule_builders.first #: RuleBuilder
        lineno = rule_builder ? rule_builder.line : 0
        lhs = rule_builder.lhs #: Lexer::Token::Base
        @rules << Rule.new(id: @rule_counter.increment, _lhs: @accept_symbol.id, _rhs: [lhs, @eof_symbol.id], token_code: nil, lineno: lineno)
      end
    end

    # Collect symbols from rules
    #
    # @rbs () -> void
    def collect_symbols
      @rules.flat_map(&:_rhs).each do |s|
        case s
        when Lrama::Lexer::Token::Char
          add_term(id: s)
        when Lrama::Lexer::Token::Base
          # skip
        else
          raise "Unknown class: #{s}"
        end
      end

      terms.freeze
    end

    # @rbs () -> void
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
    #
    # @rbs () -> void
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

    # @rbs () -> Array[Grammar::Symbol]
    def fill_symbols
      fill_symbol_number
      fill_nterm_type(@types)
      fill_printer(@printers)
      fill_destructor(@destructors)
      fill_error_token(@error_tokens)
      sort_by_number!
    end

    # @rbs () -> Array[Rule]
    def fill_sym_to_rules
      @rules.each do |rule|
        key = rule.lhs.number
        @sym_to_rules[key] ||= []
        @sym_to_rules[key] << rule
      end
    end

    # @rbs () -> void
    def validate_no_precedence_for_nterm!
      errors = [] #: Array[String]

      nterms.each do |nterm|
        next if nterm.precedence.nil?

        errors << "[BUG] Precedence #{nterm.name} (line: #{nterm.precedence.lineno}) is defined for nonterminal symbol (line: #{nterm.id.first_line}). Precedence can be defined for only terminal symbol."
      end

      return if errors.empty?

      raise errors.join("\n")
    end

    # @rbs () -> void
    def validate_rule_lhs_is_nterm!
      errors = [] #: Array[String]

      rules.each do |rule|
        next if rule.lhs.nterm?

        errors << "[BUG] LHS of #{rule.display_name} (line: #{rule.lineno}) is terminal symbol. It should be nonterminal symbol."
      end

      return if errors.empty?

      raise errors.join("\n")
    end

    # # @rbs () -> void
    def validate_duplicated_precedence!
      errors = [] #: Array[String]
      seen = {} #: Hash[String, Precedence]

      precedences.each do |prec|
        s_value = prec.s_value
        if first = seen[s_value]
          errors << "%#{prec.type} redeclaration for #{s_value} (line: #{prec.lineno}) previous declaration was %#{first.type} (line: #{first.lineno})"
        else
          seen[s_value] = prec
        end
      end

      return if errors.empty?

      raise errors.join("\n")
    end

    # @rbs () -> void
    def set_locations
      @locations = @locations || @rules.any? {|rule| rule.contains_at_reference? }
    end
  end
end
