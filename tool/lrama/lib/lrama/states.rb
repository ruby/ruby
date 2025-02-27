# frozen_string_literal: true

require "forwardable"
require_relative "report/duration"
require_relative "states/item"

module Lrama
  # States is passed to a template file
  #
  # "Efficient Computation of LALR(1) Look-Ahead Sets"
  #   https://dl.acm.org/doi/pdf/10.1145/69622.357187
  class States
    extend Forwardable
    include Lrama::Report::Duration

    def_delegators "@grammar", :symbols, :terms, :nterms, :rules,
      :accept_symbol, :eof_symbol, :undef_symbol, :find_symbol_by_s_value!

    attr_reader :states, :reads_relation, :includes_relation, :lookback_relation

    def initialize(grammar, trace_state: false)
      @grammar = grammar
      @trace_state = trace_state

      @states = []

      # `DR(p, A) = {t ∈ T | p -(A)-> r -(t)-> }`
      #   where p is state, A is nterm, t is term.
      #
      # `@direct_read_sets` is a hash whose
      # key is [state.id, nterm.token_id],
      # value is bitmap of term.
      @direct_read_sets = {}

      # Reads relation on nonterminal transitions (pair of state and nterm)
      # `(p, A) reads (r, C) iff p -(A)-> r -(C)-> and C =>* ε`
      #   where p, r are state, A, C are nterm.
      #
      # `@reads_relation` is a hash whose
      # key is [state.id, nterm.token_id],
      # value is array of [state.id, nterm.token_id].
      @reads_relation = {}

      # `Read(p, A) =s DR(p, A) ∪ ∪{Read(r, C) | (p, A) reads (r, C)}`
      #
      # `@read_sets` is a hash whose
      # key is [state.id, nterm.token_id],
      # value is bitmap of term.
      @read_sets = {}

      # `(p, A) includes (p', B) iff B -> βAγ, γ =>* ε, p' -(β)-> p`
      #   where p, p' are state, A, B are nterm, β, γ is sequence of symbol.
      #
      # `@includes_relation` is a hash whose
      # key is [state.id, nterm.token_id],
      # value is array of [state.id, nterm.token_id].
      @includes_relation = {}

      # `(q, A -> ω) lookback (p, A) iff p -(ω)-> q`
      #   where p, q are state, A -> ω is rule, A is nterm, ω is sequence of symbol.
      #
      # `@lookback_relation` is a hash whose
      # key is [state.id, rule.id],
      # value is array of [state.id, nterm.token_id].
      @lookback_relation = {}

      # `Follow(p, A) =s Read(p, A) ∪ ∪{Follow(p', B) | (p, A) includes (p', B)}`
      #
      # `@follow_sets` is a hash whose
      # key is [state.id, rule.id],
      # value is bitmap of term.
      @follow_sets = {}

      # `LA(q, A -> ω) = ∪{Follow(p, A) | (q, A -> ω) lookback (p, A)`
      #
      # `@la` is a hash whose
      # key is [state.id, rule.id],
      # value is bitmap of term.
      @la = {}
    end

    def compute
      # Look Ahead Sets
      report_duration(:compute_lr0_states) { compute_lr0_states }
      report_duration(:compute_direct_read_sets) { compute_direct_read_sets }
      report_duration(:compute_reads_relation) { compute_reads_relation }
      report_duration(:compute_read_sets) { compute_read_sets }
      report_duration(:compute_includes_relation) { compute_includes_relation }
      report_duration(:compute_lookback_relation) { compute_lookback_relation }
      report_duration(:compute_follow_sets) { compute_follow_sets }
      report_duration(:compute_look_ahead_sets) { compute_look_ahead_sets }

      # Conflicts
      report_duration(:compute_conflicts) { compute_conflicts }

      report_duration(:compute_default_reduction) { compute_default_reduction }
    end

    def compute_ielr
      report_duration(:split_states) { split_states }
      report_duration(:compute_direct_read_sets) { compute_direct_read_sets }
      report_duration(:compute_reads_relation) { compute_reads_relation }
      report_duration(:compute_read_sets) { compute_read_sets }
      report_duration(:compute_includes_relation) { compute_includes_relation }
      report_duration(:compute_lookback_relation) { compute_lookback_relation }
      report_duration(:compute_follow_sets) { compute_follow_sets }
      report_duration(:compute_look_ahead_sets) { compute_look_ahead_sets }
      report_duration(:compute_conflicts) { compute_conflicts }

      report_duration(:compute_default_reduction) { compute_default_reduction }
    end

    def reporter
      StatesReporter.new(self)
    end

    def states_count
      @states.count
    end

    def direct_read_sets
      @direct_read_sets.transform_values do |v|
        bitmap_to_terms(v)
      end
    end

    def read_sets
      @read_sets.transform_values do |v|
        bitmap_to_terms(v)
      end
    end

    def follow_sets
      @follow_sets.transform_values do |v|
        bitmap_to_terms(v)
      end
    end

    def la
      @la.transform_values do |v|
        bitmap_to_terms(v)
      end
    end

    def sr_conflicts_count
      @sr_conflicts_count ||= @states.flat_map(&:sr_conflicts).count
    end

    def rr_conflicts_count
      @rr_conflicts_count ||= @states.flat_map(&:rr_conflicts).count
    end

    private

    def trace_state
      if @trace_state
        yield STDERR
      end
    end

    def create_state(accessing_symbol, kernels, states_created)
      # A item can appear in some states,
      # so need to use `kernels` (not `kernels.first`) as a key.
      #
      # For example...
      #
      # %%
      # program: '+' strings_1
      #        | '-' strings_2
      #        ;
      #
      # strings_1: string_1
      #          ;
      #
      # strings_2: string_1
      #          | string_2
      #          ;
      #
      # string_1: string
      #         ;
      #
      # string_2: string '+'
      #         ;
      #
      # string: tSTRING
      #       ;
      # %%
      #
      # For these grammar, there are 2 states
      #
      # State A
      #    string_1: string •
      #
      # State B
      #    string_1: string •
      #    string_2: string • '+'
      #
      return [states_created[kernels], false] if states_created[kernels]

      state = State.new(@states.count, accessing_symbol, kernels)
      @states << state
      states_created[kernels] = state

      return [state, true]
    end

    def setup_state(state)
      # closure
      closure = []
      visited = {}
      queued = {}
      items = state.kernels.dup

      items.each do |item|
        queued[item] = true
      end

      while (item = items.shift) do
        visited[item] = true

        if (sym = item.next_sym) && sym.nterm?
          @grammar.find_rules_by_symbol!(sym).each do |rule|
            i = Item.new(rule: rule, position: 0)
            next if queued[i]
            closure << i
            items << i
            queued[i] = true
          end
        end
      end

      state.closure = closure.sort_by {|i| i.rule.id }

      # Trace
      trace_state do |out|
        out << "Closure: input\n"
        state.kernels.each do |item|
          out << "  #{item.display_rest}\n"
        end
        out << "\n\n"
        out << "Closure: output\n"
        state.items.each do |item|
          out << "  #{item.display_rest}\n"
        end
        out << "\n\n"
      end

      # shift & reduce
      state.compute_shifts_reduces
    end

    def enqueue_state(states, state)
      # Trace
      previous = state.kernels.first.previous_sym
      trace_state do |out|
        out << sprintf("state_list_append (state = %d, symbol = %d (%s))\n",
          @states.count, previous.number, previous.display_name)
      end

      states << state
    end

    def compute_lr0_states
      # State queue
      states = []
      states_created = {}

      state, _ = create_state(symbols.first, [Item.new(rule: @grammar.rules.first, position: 0)], states_created)
      enqueue_state(states, state)

      while (state = states.shift) do
        # Trace
        #
        # Bison 3.8.2 renders "(reached by "end-of-input")" for State 0 but
        # I think it is not correct...
        previous = state.kernels.first.previous_sym
        trace_state do |out|
          out << "Processing state #{state.id} (reached by #{previous.display_name})\n"
        end

        setup_state(state)

        state.shifts.each do |shift|
          new_state, created = create_state(shift.next_sym, shift.next_items, states_created)
          state.set_items_to_state(shift.next_items, new_state)
          if created
            enqueue_state(states, new_state)
            new_state.append_predecessor(state)
          end
        end
      end
    end

    def nterm_transitions
      a = []

      @states.each do |state|
        state.nterm_transitions.each do |shift, next_state|
          nterm = shift.next_sym
          a << [state, nterm, next_state]
        end
      end

      a
    end

    def compute_direct_read_sets
      @states.each do |state|
        state.nterm_transitions.each do |shift, next_state|
          nterm = shift.next_sym

          ary = next_state.term_transitions.map do |shift, _|
            shift.next_sym.number
          end

          key = [state.id, nterm.token_id]
          @direct_read_sets[key] = Bitmap.from_array(ary)
        end
      end
    end

    def compute_reads_relation
      @states.each do |state|
        state.nterm_transitions.each do |shift, next_state|
          nterm = shift.next_sym
          next_state.nterm_transitions.each do |shift2, _next_state2|
            nterm2 = shift2.next_sym
            if nterm2.nullable
              key = [state.id, nterm.token_id]
              @reads_relation[key] ||= []
              @reads_relation[key] << [next_state.id, nterm2.token_id]
            end
          end
        end
      end
    end

    def compute_read_sets
      sets = nterm_transitions.map do |state, nterm, next_state|
        [state.id, nterm.token_id]
      end

      @read_sets = Digraph.new(sets, @reads_relation, @direct_read_sets).compute
    end

    # Execute transition of state by symbols
    # then return final state.
    def transition(state, symbols)
      symbols.each do |sym|
        state = state.transition(sym)
      end

      state
    end

    def compute_includes_relation
      @states.each do |state|
        state.nterm_transitions.each do |shift, next_state|
          nterm = shift.next_sym
          @grammar.find_rules_by_symbol!(nterm).each do |rule|
            i = rule.rhs.count - 1

            while (i > -1) do
              sym = rule.rhs[i]

              break if sym.term?
              state2 = transition(state, rule.rhs[0...i])
              # p' = state, B = nterm, p = state2, A = sym
              key = [state2.id, sym.token_id]
              # TODO: need to omit if state == state2 ?
              @includes_relation[key] ||= []
              @includes_relation[key] << [state.id, nterm.token_id]
              break unless sym.nullable
              i -= 1
            end
          end
        end
      end
    end

    def compute_lookback_relation
      @states.each do |state|
        state.nterm_transitions.each do |shift, next_state|
          nterm = shift.next_sym
          @grammar.find_rules_by_symbol!(nterm).each do |rule|
            state2 = transition(state, rule.rhs)
            # p = state, A = nterm, q = state2, A -> ω = rule
            key = [state2.id, rule.id]
            @lookback_relation[key] ||= []
            @lookback_relation[key] << [state.id, nterm.token_id]
          end
        end
      end
    end

    def compute_follow_sets
      sets = nterm_transitions.map do |state, nterm, next_state|
        [state.id, nterm.token_id]
      end

      @follow_sets = Digraph.new(sets, @includes_relation, @read_sets).compute
    end

    def compute_look_ahead_sets
      @states.each do |state|
        rules.each do |rule|
          ary = @lookback_relation[[state.id, rule.id]]
          next unless ary

          ary.each do |state2_id, nterm_token_id|
            # q = state, A -> ω = rule, p = state2, A = nterm
            follows = @follow_sets[[state2_id, nterm_token_id]]

            next if follows == 0

            key = [state.id, rule.id]
            @la[key] ||= 0
            look_ahead = @la[key] | follows
            @la[key] |= look_ahead

            # No risk of conflict when
            # * the state only has single reduce
            # * the state only has nterm_transitions (GOTO)
            next if state.reduces.count == 1 && state.term_transitions.count == 0

            state.set_look_ahead(rule, bitmap_to_terms(look_ahead))
          end
        end
      end
    end

    def bitmap_to_terms(bit)
      ary = Bitmap.to_array(bit)
      ary.map do |i|
        @grammar.find_symbol_by_number!(i)
      end
    end

    def compute_conflicts
      compute_shift_reduce_conflicts
      compute_reduce_reduce_conflicts
    end

    def compute_shift_reduce_conflicts
      states.each do |state|
        state.shifts.each do |shift|
          state.reduces.each do |reduce|
            sym = shift.next_sym

            next unless reduce.look_ahead
            next unless reduce.look_ahead.include?(sym)

            # Shift/Reduce conflict
            shift_prec = sym.precedence
            reduce_prec = reduce.item.rule.precedence

            # Can resolve only when both have prec
            unless shift_prec && reduce_prec
              state.conflicts << State::ShiftReduceConflict.new(symbols: [sym], shift: shift, reduce: reduce)
              next
            end

            case
            when shift_prec < reduce_prec
              # Reduce is selected
              state.resolved_conflicts << State::ResolvedConflict.new(symbol: sym, reduce: reduce, which: :reduce)
              shift.not_selected = true
              next
            when shift_prec > reduce_prec
              # Shift is selected
              state.resolved_conflicts << State::ResolvedConflict.new(symbol: sym, reduce: reduce, which: :shift)
              reduce.add_not_selected_symbol(sym)
              next
            end

            # shift_prec == reduce_prec, then check associativity
            case sym.precedence.type
            when :precedence
              # %precedence only specifies precedence and not specify associativity
              # then a conflict is unresolved if precedence is same.
              state.conflicts << State::ShiftReduceConflict.new(symbols: [sym], shift: shift, reduce: reduce)
              next
            when :right
              # Shift is selected
              state.resolved_conflicts << State::ResolvedConflict.new(symbol: sym, reduce: reduce, which: :shift, same_prec: true)
              reduce.add_not_selected_symbol(sym)
              next
            when :left
              # Reduce is selected
              state.resolved_conflicts << State::ResolvedConflict.new(symbol: sym, reduce: reduce, which: :reduce, same_prec: true)
              shift.not_selected = true
              next
            when :nonassoc
              # Can not resolve
              #
              # nonassoc creates "run-time" error, precedence creates "compile-time" error.
              # Then omit both the shift and reduce.
              #
              # https://www.gnu.org/software/bison/manual/html_node/Using-Precedence.html
              state.resolved_conflicts << State::ResolvedConflict.new(symbol: sym, reduce: reduce, which: :error)
              shift.not_selected = true
              reduce.add_not_selected_symbol(sym)
            else
              raise "Unknown precedence type. #{sym}"
            end
          end
        end
      end
    end

    def compute_reduce_reduce_conflicts
      states.each do |state|
        count = state.reduces.count

        (0...count).each do |i|
          reduce1 = state.reduces[i]
          next if reduce1.look_ahead.nil?

          ((i+1)...count).each do |j|
            reduce2 = state.reduces[j]
            next if reduce2.look_ahead.nil?

            intersection = reduce1.look_ahead & reduce2.look_ahead

            unless intersection.empty?
              state.conflicts << State::ReduceReduceConflict.new(symbols: intersection, reduce1: reduce1, reduce2: reduce2)
            end
          end
        end
      end
    end

    def compute_default_reduction
      states.each do |state|
        next if state.reduces.empty?
        # Do not set, if conflict exist
        next unless state.conflicts.empty?
        # Do not set, if shift with `error` exists.
        next if state.shifts.map(&:next_sym).include?(@grammar.error_symbol)

        state.default_reduction_rule = state.reduces.map do |r|
          [r.rule, r.rule.id, (r.look_ahead || []).count]
        end.min_by do |rule, rule_id, count|
          [-count, rule_id]
        end.first
      end
    end

    def split_states
      @states.each do |state|
        state.transitions.each do |shift, next_state|
          compute_state(state, shift, next_state)
        end
      end
    end

    def merge_lookaheads(state, filtered_lookaheads)
      return if state.kernels.all? {|item| (filtered_lookaheads[item] - state.item_lookahead_set[item]).empty? }

      state.item_lookahead_set = state.item_lookahead_set.merge {|_, v1, v2| v1 | v2 }
      state.transitions.each do |shift, next_state|
        next if next_state.lookaheads_recomputed
        compute_state(state, shift, next_state)
      end
    end

    def compute_state(state, shift, next_state)
      filtered_lookaheads = state.propagate_lookaheads(next_state)
      s = next_state.ielr_isocores.find {|st| st.compatible_lookahead?(filtered_lookaheads) }

      if s.nil?
        s = next_state.ielr_isocores.last
        new_state = State.new(@states.count, s.accessing_symbol, s.kernels)
        new_state.closure = s.closure
        new_state.compute_shifts_reduces
        s.transitions.each do |sh, next_state|
          new_state.set_items_to_state(sh.next_items, next_state)
        end
        @states << new_state
        new_state.lalr_isocore = s
        s.ielr_isocores << new_state
        s.ielr_isocores.each do |st|
          st.ielr_isocores = s.ielr_isocores
        end
        new_state.item_lookahead_set = filtered_lookaheads
        state.update_transition(shift, new_state)
      elsif(!s.lookaheads_recomputed)
        s.item_lookahead_set = filtered_lookaheads
      else
        state.update_transition(shift, s)
        merge_lookaheads(s, filtered_lookaheads)
      end
    end
  end
end
