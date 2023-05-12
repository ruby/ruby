require "forwardable"
require "lrama/lexer"

module Lrama
  Rule = Struct.new(:id, :lhs, :rhs, :code, :nullable, :precedence_sym, :lineno, keyword_init: true) do
    # TODO: Change this to display_name
    def to_s
      l = lhs.id.s_value
      r = rhs.empty? ? "ε" : rhs.map {|r| r.id.s_value }.join(", ")

      "#{l} -> #{r}"
    end

    # Used by #user_actions
    def as_comment
      l = lhs.id.s_value
      r = rhs.empty? ? "%empty" : rhs.map {|r| r.display_name }.join(" ")

      "#{l}: #{r}"
    end

    def precedence
      precedence_sym && precedence_sym.precedence
    end

    def initial_rule?
      id == 0
    end

    def translated_code
      if code
        code.translated_code
      else
        nil
      end
    end
  end

  # Symbol is both of nterm and term
  # `number` is both for nterm and term
  # `token_id` is tokentype for term, internal sequence number for nterm
  #
  # TODO: Add validation for ASCII code range for Token::Char
  Symbol = Struct.new(:id, :alias_name, :number, :tag, :term, :token_id, :nullable, :precedence, :printer, keyword_init: true) do
    attr_writer :eof_symbol, :error_symbol, :undef_symbol, :accept_symbol

    def term?
      term
    end

    def nterm?
      !term
    end

    def eof_symbol?
      !!@eof_symbol
    end

    def error_symbol?
      !!@error_symbol
    end

    def undef_symbol?
      !!@undef_symbol
    end

    def accept_symbol?
      !!@accept_symbol
    end

    def display_name
      if alias_name
        alias_name
      else
        id.s_value
      end
    end

    # name for yysymbol_kind_t
    #
    # See: b4_symbol_kind_base
    def enum_name
      case
      when accept_symbol?
        name = "YYACCEPT"
      when eof_symbol?
        name = "YYEOF"
      when term? && id.type == Token::Char
        if alias_name
          name = number.to_s + alias_name
        else
          name = number.to_s + id.s_value
        end
      when term? && id.type == Token::Ident
        name = id.s_value
      when nterm? && (id.s_value.include?("$") || id.s_value.include?("@"))
        name = number.to_s + id.s_value
      when nterm?
        name = id.s_value
      else
        raise "Unexpected #{self}"
      end

      "YYSYMBOL_" + name.gsub(/[^a-zA-Z_0-9]+/, "_")
    end

    # comment for yysymbol_kind_t
    def comment
      case
      when accept_symbol?
        # YYSYMBOL_YYACCEPT
        id.s_value
      when eof_symbol?
        # YYEOF
        alias_name
      when (term? && 0 < token_id && token_id < 128)
        # YYSYMBOL_3_backslash_, YYSYMBOL_14_
        alias_name || id.s_value
      when id.s_value.include?("$") || id.s_value.include?("@")
        # YYSYMBOL_21_1
        id.s_value
      else
        # YYSYMBOL_keyword_class, YYSYMBOL_strings_1
        alias_name || id.s_value
      end
    end
  end

  Type = Struct.new(:id, :tag, keyword_init: true)

  Code = Struct.new(:type, :token_code, keyword_init: true) do
    extend Forwardable

    def_delegators "token_code", :s_value, :line, :column, :references

    # $$, $n, @$, @n is translated to C code
    def translated_code
      case type
      when :user_code
        translated_user_code
      when :initial_action
        translated_initial_action_code
      end
    end

    # * ($1) error
    # * ($$) *yyvaluep
    # * (@1) error
    # * (@$) *yylocationp
    def translated_printer_code(tag)
      t_code = s_value.dup

      references.reverse.each do |ref|
        first_column = ref.first_column
        last_column = ref.last_column

        case
        when ref.number == "$" && ref.type == :dollar # $$
          # Omit "<>"
          member = tag.s_value[1..-2]
          str = "((*yyvaluep).#{member})"
        when ref.number == "$" && ref.type == :at # @$
          str = "(*yylocationp)"
        when ref.type == :dollar # $n
          raise "$#{ref.number} can not be used in %printer."
        when ref.type == :at # @n
          raise "@#{ref.number} can not be used in %printer."
        else
          raise "Unexpected. #{code}, #{ref}"
        end

        t_code[first_column..last_column] = str
      end

      return t_code
    end


    private

    # * ($1) yyvsp[i]
    # * ($$) yyval
    # * (@1) yylsp[i]
    # * (@$) yyloc
    def translated_user_code
      t_code = s_value.dup

      references.reverse.each do |ref|
        first_column = ref.first_column
        last_column = ref.last_column

        case
        when ref.number == "$" && ref.type == :dollar # $$
          # Omit "<>"
          member = ref.tag.s_value[1..-2]
          str = "(yyval.#{member})"
        when ref.number == "$" && ref.type == :at # @$
          str = "(yyloc)"
        when ref.type == :dollar # $n
          i = -ref.position_in_rhs + ref.number
          # Omit "<>"
          member = ref.tag.s_value[1..-2]
          str = "(yyvsp[#{i}].#{member})"
        when ref.type == :at # @n
          i = -ref.position_in_rhs + ref.number
          str = "(yylsp[#{i}])"
        else
          raise "Unexpected. #{code}, #{ref}"
        end

        t_code[first_column..last_column] = str
      end

      return t_code
    end

    # * ($1) error
    # * ($$) yylval
    # * (@1) error
    # * (@$) yylloc
    def translated_initial_action_code
      t_code = s_value.dup

      references.reverse.each do |ref|
        first_column = ref.first_column
        last_column = ref.last_column

        case
        when ref.number == "$" && ref.type == :dollar # $$
          str = "yylval"
        when ref.number == "$" && ref.type == :at # @$
          str = "yylloc"
        when ref.type == :dollar # $n
          raise "$#{ref.number} can not be used in initial_action."
        when ref.type == :at # @n
          raise "@#{ref.number} can not be used in initial_action."
        else
          raise "Unexpected. #{code}, #{ref}"
        end

        t_code[first_column..last_column] = str
      end

      return t_code
    end
  end

  # type: :dollar or :at
  # ex_tag: "$<tag>1" (Optional)
  Reference = Struct.new(:type, :number, :ex_tag, :first_column, :last_column, :referring_symbol, :position_in_rhs, keyword_init: true) do
    def tag
      if ex_tag
        ex_tag
      else
        referring_symbol.tag
      end
    end
  end

  Precedence = Struct.new(:type, :precedence, keyword_init: true) do
    include Comparable

    def <=>(other)
      self.precedence <=> other.precedence
    end
  end

  Printer = Struct.new(:ident_or_tags, :code, :lineno, keyword_init: true) do
    def translated_code(member)
      code.translated_printer_code(member)
    end
  end

  Union = Struct.new(:code, :lineno, keyword_init: true) do
    def braces_less_code
      # Remove braces
      code.s_value[1..-2]
    end
  end

  Token = Lrama::Lexer::Token

  # Grammar is the result of parsing an input grammar file
  class Grammar
    # Grammar file information not used by States but by Output
    Aux = Struct.new(:prologue_first_lineno, :prologue, :epilogue_first_lineno, :epilogue, keyword_init: true)

    attr_reader :eof_symbol, :error_symbol, :undef_symbol, :accept_symbol, :aux
    attr_accessor :union, :expect,
                  :printers,
                  :lex_param, :parse_param, :initial_action,
                  :symbols, :types,
                  :rules, :_rules,
                  :sym_to_rules

    def initialize
      @printers = []
      @symbols = []
      @types = []
      @_rules = []
      @rules = []
      @sym_to_rules = {}
      @empty_symbol = nil
      @eof_symbol = nil
      @error_symbol = nil
      @undef_symbol = nil
      @accept_symbol = nil
      @aux = Aux.new

      append_special_symbols
    end

    def add_printer(ident_or_tags:, code:, lineno:)
      @printers << Printer.new(ident_or_tags: ident_or_tags, code: code, lineno: lineno)
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

    def set_precedence(sym, precedence)
      raise "" if sym.nterm?
      sym.precedence = precedence
    end

    def set_union(code, lineno)
      @union = Union.new(code: code, lineno: lineno)
    end

    def add_rule(lhs:, rhs:, lineno:)
      @_rules << [lhs, rhs, lineno]
    end

    def build_references(token_code)
      token_code.references.map! do |type, number, tag, first_column, last_column|
        Reference.new(type: type, number: number, ex_tag: tag, first_column: first_column, last_column: last_column)
      end

      token_code
    end

    def build_code(type, token_code)
      build_references(token_code)
      Code.new(type: type, token_code: token_code)
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
      replace_token_with_symbol
      fill_symbol_number
      fill_default_precedence
      fill_sym_to_rules
      fill_nterm_type
      fill_symbol_printer
      @symbols.sort_by!(&:number)
    end

    # TODO: More validation methods
    def validate!
      validate_symbol_number_uniqueness!
    end

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
        # TODO: validate uniqueness of Token#s_value and Symbol#alias_name
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
      term = add_term(id: Token.new(type: Token::Ident, s_value: "YYEOF"), alias_name: "\"end of file\"", token_id: 0)
      term.number = 0
      term.eof_symbol = true
      @eof_symbol = term

      # YYerror
      term = add_term(id: Token.new(type: Token::Ident, s_value: "YYerror"), alias_name: "error")
      term.number = 1
      term.error_symbol = true
      @error_symbol = term

      # YYUNDEF
      term = add_term(id: Token.new(type: Token::Ident, s_value: "YYUNDEF"), alias_name: "\"invalid token\"")
      term.number = 2
      term.undef_symbol = true
      @undef_symbol = term

      # $accept
      term = add_nterm(id: Token.new(type: Token::Ident, s_value: "$accept"))
      term.accept_symbol = true
      @accept_symbol = term
    end

    # 1. Add $accept rule to the top of rules
    # 2. Extract precedence and last action
    # 3. Extract action in the middle of RHS into new Empty rule
    # 4. Append id and extract action then create Rule
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
      accept = find_symbol_by_s_value!("$accept")
      eof = find_symbol_by_number!(0)
      lineno = @_rules.first ? @_rules.first[2] : 0
      @rules << Rule.new(id: @rules.count, lhs: accept, rhs: [@_rules.first[0], eof], code: nil, lineno: lineno)

      extracted_action_number = 1 # @n as nterm

      @_rules.each do |lhs, rhs, lineno|
        a = []
        rhs1 = []
        code = nil
        precedence_sym = nil

        # 2. Extract precedence and last action
        rhs.reverse.each do |r|
          case
          when r.is_a?(Symbol) # precedence_sym
            precedence_sym = r
          when (r.type == Token::User_code) && precedence_sym.nil? && code.nil? && rhs1.empty?
            code = r
          else
            rhs1 << r
          end
        end
        rhs1.reverse!

        # Bison n'th component is 1-origin
        (rhs1 + [code]).compact.each.with_index(1) do |token, i|
          if token.type == Token::User_code
            token.references.each do |ref|
              # Need to keep position_in_rhs for actions in the middle of RHS
              ref.position_in_rhs = i - 1
              next if ref.type == :at
              # $$, $n, @$, @n can be used in any actions
              number = ref.number

              if number == "$"
                # TODO: Should be postponed after middle actions are extracted?
                ref.referring_symbol = lhs
              else
                raise "Can not refer following component. #{number} >= #{i}. #{token}" if number >= i
                rhs1[number - 1].referred = true
                ref.referring_symbol = rhs1[number - 1]
              end
            end
          end
        end

        rhs2 = rhs1.map do |token|
          if token.type == Token::User_code
            prefix = token.referred ? "@" : "$@"
            new_token = Token.new(type: Token::Ident, s_value: prefix + extracted_action_number.to_s)
            extracted_action_number += 1
            a << [new_token, token]
            new_token
          else
            token
          end
        end

        # Extract actions in the middle of RHS
        # into new rules.
        a.each do |new_token, code|
          @rules << Rule.new(id: @rules.count, lhs: new_token, rhs: [], code: Code.new(type: :user_code, token_code: code), lineno: code.line)
        end

        c = code ? Code.new(type: :user_code, token_code: code) : nil
        @rules << Rule.new(id: @rules.count, lhs: lhs, rhs: rhs2, code: c, precedence_sym: precedence_sym, lineno: lineno)

        add_nterm(id: lhs)
        a.each do |new_token, _|
          add_nterm(id: new_token)
        end
      end
    end

    # Collect symbols from rules
    def collect_symbols
      @rules.flat_map(&:rhs).each do |s|
        case s
        when Token
          if s.type == Token::Char
            add_term(id: s)
          end
        when Symbol
          # skip
        else
          raise "Unknown class: #{s}"
        end
      end
    end

    # Fill #number and #token_id
    def fill_symbol_number
      # TODO: why start from 256
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
          if sym.id.type == Token::Char
            # Igonre ' on the both sides
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
            when "\'"
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

    def replace_token_with_symbol
      @rules.each do |rule|
        rule.lhs = token_to_symbol(rule.lhs)

        rule.rhs.map! do |t|
          token_to_symbol(t)
        end

        if rule.code
          rule.code.references.each do |ref|
            next if ref.type == :at

            if ref.referring_symbol.type != Token::User_code
              ref.referring_symbol = token_to_symbol(ref.referring_symbol)
            end
          end
        end
      end
    end

    def token_to_symbol(token)
      case token
      when Token
        find_symbol_by_id!(token)
      when Symbol
        token
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
            case ident_or_tag.type
            when Token::Ident
              sym.printer = printer if sym.id == ident_or_tag
            when Token::Tag
              sym.printer = printer if sym.tag == ident_or_tag
            else
              raise "Unknown token type. #{printer}"
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

      raise "Symbol number is dupulicated. #{invalid}"
    end
  end
end
