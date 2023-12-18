require "lrama/report/duration"

module Lrama
  # This is passed to a template
  class Context
    include Report::Duration

    ErrorActionNumber = -Float::INFINITY
    BaseMin = -Float::INFINITY

    # TODO: It might be better to pass `states` to Output directly?
    attr_reader :states

    def initialize(states)
      @states = states
      @yydefact = nil
      @yydefgoto = nil
      # Array of array
      @_actions = []

      compute_tables
    end

    # enum yytokentype
    def yytokentype
      @states.terms.reject do |term|
        0 < term.token_id && term.token_id < 128
      end.map do |term|
        [term.id.s_value, term.token_id, term.display_name]
      end.unshift(["YYEMPTY", -2, nil])
    end

    # enum yysymbol_kind_t
    def yysymbol_kind_t
      @states.symbols.map do |sym|
        [sym.enum_name, sym.number, sym.comment]
      end.unshift(["YYSYMBOL_YYEMPTY", -2, nil])
    end

    # State number of final (accepted) state
    def yyfinal
      @states.states.find do |state|
        state.items.find do |item|
          item.rule.lhs.id.s_value == "$accept" && item.end_of_rule?
        end
      end.id
    end

    def yylast
      @yylast
    end

    # Number of terms
    def yyntokens
      @states.terms.count
    end

    # Number of nterms
    def yynnts
      @states.nterms.count
    end

    # Number of rules
    def yynrules
      @states.rules.count
    end

    # Number of states
    def yynstates
      @states.states.count
    end

    # Last token number
    def yymaxutok
      @states.terms.map(&:token_id).max
    end

    # YYTRANSLATE
    #
    # yytranslate is a mapping from token id to symbol number
    def yytranslate
      # 2 is YYSYMBOL_YYUNDEF
      a = Array.new(yymaxutok, 2)

      @states.terms.each do |term|
        a[term.token_id] = term.number
      end

      return a
    end

    def yytranslate_inverted
      a = Array.new(@states.symbols.count, @states.undef_symbol.token_id)

      @states.terms.each do |term|
        a[term.number] = term.token_id
      end

      return a
    end

    # Mapping from rule number to line number of the rule is defined.
    # Dummy rule is appended as the first element whose value is 0
    # because 0 means error in yydefact.
    def yyrline
      a = [0]

      @states.rules.each do |rule|
        a << rule.lineno
      end

      return a
    end

    # Mapping from symbol number to its name
    def yytname
      @states.symbols.sort_by(&:number).map do |sym|
        sym.display_name
      end
    end

    def yypact_ninf
      @yypact_ninf
    end

    def yytable_ninf
      @yytable_ninf
    end

    def yypact
      @base[0...yynstates]
    end

    def yydefact
      @yydefact
    end

    def yypgoto
      @base[yynstates..-1]
    end

    def yydefgoto
      @yydefgoto
    end

    def yytable
      @table
    end

    def yycheck
      @check
    end

    def yystos
      @states.states.map do |state|
        state.accessing_symbol.number
      end
    end

    # Mapping from rule number to symbol number of LHS.
    # Dummy rule is appended as the first element whose value is 0
    # because 0 means error in yydefact.
    def yyr1
      a = [0]

      @states.rules.each do |rule|
        a << rule.lhs.number
      end

      return a
    end

    # Mapping from rule number to length of RHS.
    # Dummy rule is appended as the first element whose value is 0
    # because 0 means error in yydefact.
    def yyr2
      a = [0]

      @states.rules.each do |rule|
        a << rule.rhs.count
      end

      return a
    end

    private

    # Compute these
    #
    # See also: "src/tables.c" of Bison.
    #
    # * yydefact
    # * yydefgoto
    # * yypact and yypgoto
    # * yytable
    # * yycheck
    # * yypact_ninf
    # * yytable_ninf
    def compute_tables
      report_duration(:compute_yydefact) { compute_yydefact }
      report_duration(:compute_yydefgoto) { compute_yydefgoto }
      report_duration(:sort_actions) { sort_actions }
      # debug_sorted_actions
      report_duration(:compute_packed_table) { compute_packed_table }
    end

    def vectors_count
      @states.states.count + @states.nterms.count
    end

    # In compressed table, rule 0 is appended as an error case
    # and reduce is represented as minus number.
    def rule_id_to_action_number(rule_id)
      (rule_id + 1) * -1
    end

    # Symbol number is assigned to term first then nterm.
    # This method calculates sequence_number for nterm.
    def nterm_number_to_sequence_number(nterm_number)
      nterm_number - @states.terms.count
    end

    # Vector is states + nterms
    def nterm_number_to_vector_number(nterm_number)
      @states.states.count + (nterm_number - @states.terms.count)
    end

    def compute_yydefact
      # Default action (shift/reduce/error) for each state.
      # Index is state id, value is `rule id + 1` of a default reduction.
      @yydefact = Array.new(@states.states.count, 0)

      @states.states.each do |state|
        # Action number means
        #
        # * number = 0, default action
        # * number = -Float::INFINITY, error by %nonassoc
        # * number > 0, shift then move to state "number"
        # * number < 0, reduce by "-number" rule. Rule "number" is already added by 1.
        actions = Array.new(@states.terms.count, 0)

        if state.reduces.map(&:selected_look_ahead).any? {|la| !la.empty? }
          # Iterate reduces with reverse order so that first rule is used.
          state.reduces.reverse.each do |reduce|
            reduce.look_ahead.each do |term|
              actions[term.number] = rule_id_to_action_number(reduce.rule.id)
            end
          end
        end

        # Shift is selected when S/R conflict exists.
        state.selected_term_transitions.each do |shift, next_state|
          actions[shift.next_sym.number] = next_state.id
        end

        state.resolved_conflicts.select do |conflict|
          conflict.which == :error
        end.each do |conflict|
          actions[conflict.symbol.number] = ErrorActionNumber
        end

        # If default_reduction_rule, replace default_reduction_rule in
        # actions with zero.
        if state.default_reduction_rule
          actions.map! do |e|
            if e == rule_id_to_action_number(state.default_reduction_rule.id)
              0
            else
              e
            end
          end
        end

        # If no default_reduction_rule, default behavior is an
        # error then replace ErrorActionNumber with zero.
        if !state.default_reduction_rule
          actions.map! do |e|
            if e == ErrorActionNumber
              0
            else
              e
            end
          end
        end

        s = actions.each_with_index.map do |n, i|
          [i, n]
        end.select do |i, n|
          # Remove default_reduction_rule entries
          n != 0
        end

        if s.count != 0
          # Entry of @_actions is an array of
          #
          # * State id
          # * Array of tuple, [from, to] where from is term number and to is action.
          # * The number of "Array of tuple" used by sort_actions
          # * "width" used by sort_actions
          @_actions << [state.id, s, s.count, s.last[0] - s.first[0] + 1]
        end

        @yydefact[state.id] = state.default_reduction_rule ? state.default_reduction_rule.id + 1 : 0
      end
    end

    def compute_yydefgoto
      # Default GOTO (nterm transition) for each nterm.
      # Index is sequence number of nterm, value is state id
      # of a default nterm transition destination.
      @yydefgoto = Array.new(@states.nterms.count, 0)
      # Mapping from nterm to next_states
      nterm_to_next_states = {}

      @states.states.each do |state|
        state.nterm_transitions.each do |shift, next_state|
          key = shift.next_sym
          nterm_to_next_states[key] ||= []
          nterm_to_next_states[key] << [state, next_state] # [from_state, to_state]
        end
      end

      @states.nterms.each do |nterm|
        if !(states = nterm_to_next_states[nterm])
          default_goto = 0
          not_default_gotos = []
        else
          default_state = states.map(&:last).group_by {|s| s }.max_by {|_, v| v.count }.first
          default_goto = default_state.id
          not_default_gotos = []
          states.each do |from_state, to_state|
            next if to_state.id == default_goto
            not_default_gotos << [from_state.id, to_state.id]
          end
        end

        k = nterm_number_to_sequence_number(nterm.number)
        @yydefgoto[k] = default_goto

        if not_default_gotos.count != 0
          v = nterm_number_to_vector_number(nterm.number)

          # Entry of @_actions is an array of
          #
          # * Nterm number as vector number
          # * Array of tuple, [from, to] where from is state number and to is state number.
          # * The number of "Array of tuple" used by sort_actions
          # * "width" used by sort_actions
          @_actions << [v, not_default_gotos, not_default_gotos.count, not_default_gotos.last[0] - not_default_gotos.first[0] + 1]
        end
      end
    end

    def sort_actions
      # This is not same with #sort_actions
      #
      # @sorted_actions = @_actions.sort_by do |_, _, count, width|
      #   [-width, -count]
      # end

      @sorted_actions = []

      @_actions.each do |action|
        if @sorted_actions.empty?
          @sorted_actions << action
          next
        end

        j = @sorted_actions.count - 1
        _state_id, _froms_and_tos, count, width = action

        while (j >= 0) do
          case
          when @sorted_actions[j][3] < width
            j -= 1
          when @sorted_actions[j][3] == width && @sorted_actions[j][2] < count
            j -= 1
          else
            break
          end
        end

        @sorted_actions.insert(j + 1, action)
      end
    end

    def debug_sorted_actions
      ary = Array.new
      @sorted_actions.each do |state_id, froms_and_tos, count, width|
        ary[state_id] = [state_id, froms_and_tos, count, width]
      end

      print sprintf("table_print:\n\n")

      print sprintf("order [\n")
      vectors_count.times do |i|
        print sprintf("%d, ", @sorted_actions[i] ? @sorted_actions[i][0] : 0)
        print "\n" if i % 10 == 9
      end
      print sprintf("]\n\n")

      print sprintf("width [\n")
      vectors_count.times do |i|
        print sprintf("%d, ", ary[i] ? ary[i][3] : 0)
        print "\n" if i % 10 == 9
      end
      print sprintf("]\n\n")

      print sprintf("tally [\n")
      vectors_count.times do |i|
        print sprintf("%d, ", ary[i] ? ary[i][2] : 0)
        print "\n" if i % 10 == 9
      end
      print sprintf("]\n\n")
    end

    def compute_packed_table
      # yypact and yypgoto
      @base = Array.new(vectors_count, BaseMin)
      # yytable
      @table = []
      # yycheck
      @check = []
      # Key is froms_and_tos, value is index position
      pushed = {}
      userd_res = {}
      lowzero = 0
      high = 0

      @sorted_actions.each do |state_id, froms_and_tos, _, _|
        if (res = pushed[froms_and_tos])
          @base[state_id] = res
          next
        end

        res = lowzero - froms_and_tos.first[0]

        while true do
          ok = true

          froms_and_tos.each do |from, to|
            loc = res + from

            if @table[loc]
              # If the cell of table is set, can not use the cell.
              ok = false
              break
            end
          end

          if ok && userd_res[res]
            ok = false
          end

          if ok
            break
          else
            res += 1
          end
        end

        loc = 0

        froms_and_tos.each do |from, to|
          loc = res + from

          @table[loc] = to
          @check[loc] = from
        end

        while (@table[lowzero]) do
          lowzero += 1
        end

        high = loc if high < loc

        @base[state_id] = res
        pushed[froms_and_tos] = res
        userd_res[res] = true
      end

      @yylast = high

      # replace_ninf
      @yypact_ninf = (@base.select {|i| i != BaseMin } + [0]).min - 1
      @base.map! do |i|
        case i
        when BaseMin
          @yypact_ninf
        else
          i
        end
      end

      @yytable_ninf = (@table.compact.select {|i| i != ErrorActionNumber } + [0]).min - 1
      @table.map! do |i|
        case i
        when nil
          0
        when ErrorActionNumber
          @yytable_ninf
        else
          i
        end
      end

      @check.map! do |i|
        case i
        when nil
          -1
        else
          i
        end
      end
    end
  end
end
