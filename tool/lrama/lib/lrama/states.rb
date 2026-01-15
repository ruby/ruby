# rbs_inline: enabled
# frozen_string_literal: true

require "forwardable"
require_relative "tracer/duration"
require_relative "state/item"

module Lrama
  # States is passed to a template file
  #
  # "Efficient Computation of LALR(1) Look-Ahead Sets"
  #   https://dl.acm.org/doi/pdf/10.1145/69622.357187
  class States
    # TODO: rbs-inline 0.11.0 doesn't support instance variables.
    #       Move these type declarations above instance variable definitions, once it's supported.
    #       see: https://github.com/soutaro/rbs-inline/pull/149
    #
    # @rbs!
    #   type state_id = Integer
    #   type rule_id = Integer
    #
    #   include Grammar::_DelegatedMethods
    #
    #   @grammar: Grammar
    #   @tracer: Tracer
    #   @states: Array[State]
    #   @direct_read_sets: Hash[State::Action::Goto, Bitmap::bitmap]
    #   @reads_relation: Hash[State::Action::Goto, Array[State::Action::Goto]]
    #   @read_sets: Hash[State::Action::Goto, Bitmap::bitmap]
    #   @includes_relation: Hash[State::Action::Goto, Array[State::Action::Goto]]
    #   @lookback_relation: Hash[state_id, Hash[rule_id, Array[State::Action::Goto]]]
    #   @follow_sets: Hash[State::Action::Goto, Bitmap::bitmap]
    #   @la: Hash[state_id, Hash[rule_id, Bitmap::bitmap]]

    extend Forwardable
    include Lrama::Tracer::Duration

    def_delegators "@grammar", :symbols, :terms, :nterms, :rules, :precedences,
      :accept_symbol, :eof_symbol, :undef_symbol, :find_symbol_by_s_value!, :ielr_defined?

    attr_reader :states #: Array[State]
    attr_reader :reads_relation #: Hash[State::Action::Goto, Array[State::Action::Goto]]
    attr_reader :includes_relation #: Hash[State::Action::Goto, Array[State::Action::Goto]]
    attr_reader :lookback_relation #: Hash[state_id, Hash[rule_id, Array[State::Action::Goto]]]

    # @rbs (Grammar grammar, Tracer tracer) -> void
    def initialize(grammar, tracer)
      @grammar = grammar
      @tracer = tracer

      @states = []

      # `DR(p, A) = {t ∈ T | p -(A)-> r -(t)-> }`
      #   where p is state, A is nterm, t is term.
      #
      # `@direct_read_sets` is a hash whose
      # key is goto,
      # value is bitmap of term.
      @direct_read_sets = {}

      # Reads relation on nonterminal transitions (pair of state and nterm)
      # `(p, A) reads (r, C) iff p -(A)-> r -(C)-> and C =>* ε`
      #   where p, r are state, A, C are nterm.
      #
      # `@reads_relation` is a hash whose
      # key is goto,
      # value is array of goto.
      @reads_relation = {}

      # `Read(p, A) =s DR(p, A) ∪ ∪{Read(r, C) | (p, A) reads (r, C)}`
      #
      # `@read_sets` is a hash whose
      # key is goto,
      # value is bitmap of term.
      @read_sets = {}

      # `(p, A) includes (p', B) iff B -> βAγ, γ =>* ε, p' -(β)-> p`
      #   where p, p' are state, A, B are nterm, β, γ is sequence of symbol.
      #
      # `@includes_relation` is a hash whose
      # key is goto,
      # value is array of goto.
      @includes_relation = {}

      # `(q, A -> ω) lookback (p, A) iff p -(ω)-> q`
      #   where p, q are state, A -> ω is rule, A is nterm, ω is sequence of symbol.
      #
      # `@lookback_relation` is a two-stage hash whose
      # first key is state_id,
      # second key is rule_id,
      # value is array of goto.
      @lookback_relation = {}

      # `Follow(p, A) =s Read(p, A) ∪ ∪{Follow(p', B) | (p, A) includes (p', B)}`
      #
      # `@follow_sets` is a hash whose
      # key is goto,
      # value is bitmap of term.
      @follow_sets = {}

      # `LA(q, A -> ω) = ∪{Follow(p, A) | (q, A -> ω) lookback (p, A)`
      #
      # `@la` is a two-stage hash whose
      # first key is state_id,
      # second key is rule_id,
      # value is bitmap of term.
      @la = {}
    end

    # @rbs () -> void
    def compute
      report_duration(:compute_lr0_states) { compute_lr0_states }

      # Look Ahead Sets
      report_duration(:compute_look_ahead_sets) { compute_look_ahead_sets }

      # Conflicts
      report_duration(:compute_conflicts) { compute_conflicts(:lalr) }

      report_duration(:compute_default_reduction) { compute_default_reduction }
    end

    # @rbs () -> void
    def compute_ielr
      # Preparation
      report_duration(:clear_conflicts) { clear_conflicts }
      # Phase 1
      report_duration(:compute_predecessors) { compute_predecessors }
      report_duration(:compute_follow_kernel_items) { compute_follow_kernel_items }
      report_duration(:compute_always_follows) { compute_always_follows }
      report_duration(:compute_goto_follows) { compute_goto_follows }
      # Phase 2
      report_duration(:compute_inadequacy_annotations) { compute_inadequacy_annotations }
      # Phase 3
      report_duration(:split_states) { split_states }
      # Phase 4
      report_duration(:clear_look_ahead_sets) { clear_look_ahead_sets }
      report_duration(:compute_look_ahead_sets) { compute_look_ahead_sets }
      # Phase 5
      report_duration(:compute_conflicts) { compute_conflicts(:ielr) }
      report_duration(:compute_default_reduction) { compute_default_reduction }
    end

    # @rbs () -> Integer
    def states_count
      @states.count
    end

    # @rbs () -> Hash[State::Action::Goto, Array[Grammar::Symbol]]
    def direct_read_sets
      @_direct_read_sets ||= @direct_read_sets.transform_values do |v|
        bitmap_to_terms(v)
      end
    end

    # @rbs () -> Hash[State::Action::Goto, Array[Grammar::Symbol]]
    def read_sets
      @_read_sets ||= @read_sets.transform_values do |v|
        bitmap_to_terms(v)
      end
    end

    # @rbs () -> Hash[State::Action::Goto, Array[Grammar::Symbol]]
    def follow_sets
      @_follow_sets ||= @follow_sets.transform_values do |v|
        bitmap_to_terms(v)
      end
    end

    # @rbs () -> Hash[state_id, Hash[rule_id, Array[Grammar::Symbol]]]
    def la
      @_la ||= @la.transform_values do |second_hash|
        second_hash.transform_values do |v|
          bitmap_to_terms(v)
        end
      end
    end

    # @rbs () -> Integer
    def sr_conflicts_count
      @sr_conflicts_count ||= @states.flat_map(&:sr_conflicts).count
    end

    # @rbs () -> Integer
    def rr_conflicts_count
      @rr_conflicts_count ||= @states.flat_map(&:rr_conflicts).count
    end

    # @rbs (Logger logger) -> void
    def validate!(logger)
      validate_conflicts_within_threshold!(logger)
    end

    def compute_la_sources_for_conflicted_states
      reflexive = {}
      @states.each do |state|
        state.nterm_transitions.each do |goto|
          reflexive[goto] = [goto]
        end
      end

      # compute_read_sets
      read_sets = Digraph.new(nterm_transitions, @reads_relation, reflexive).compute
      # compute_follow_sets
      follow_sets = Digraph.new(nterm_transitions, @includes_relation, read_sets).compute

      @states.select(&:has_conflicts?).each do |state|
        lookback_relation_on_state = @lookback_relation[state.id]
        next unless lookback_relation_on_state
        rules.each do |rule|
          ary = lookback_relation_on_state[rule.id]
          next unless ary

          sources = {}

          ary.each do |goto|
            source = follow_sets[goto]

            next unless source

            source.each do |goto2|
              tokens = direct_read_sets[goto2]
              tokens.each do |token|
                sources[token] ||= []
                sources[token] |= [goto2]
              end
            end
          end

          state.set_look_ahead_sources(rule, sources)
        end
      end
    end

    private

    # @rbs (Grammar::Symbol accessing_symbol, Array[State::Item] kernels, Hash[Array[State::Item], State] states_created) -> [State, bool]
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

    # @rbs (State state) -> void
    def setup_state(state)
      # closure
      closure = []
      queued = {}
      items = state.kernels.dup

      items.each do |item|
        queued[item.rule_id] = true if item.position == 0
      end

      while (item = items.shift) do
        if (sym = item.next_sym) && sym.nterm?
          @grammar.find_rules_by_symbol!(sym).each do |rule|
            next if queued[rule.id]
            i = State::Item.new(rule: rule, position: 0)
            closure << i
            items << i
            queued[i.rule_id] = true
          end
        end
      end

      state.closure = closure.sort_by {|i| i.rule.id }

      # Trace
      @tracer.trace_closure(state)

      # shift & reduce
      state.compute_transitions_and_reduces
    end

    # @rbs (Array[State] states, State state) -> void
    def enqueue_state(states, state)
      # Trace
      @tracer.trace_state_list_append(@states.count, state)

      states << state
    end

    # @rbs () -> void
    def compute_lr0_states
      # State queue
      states = []
      states_created = {}

      state, _ = create_state(symbols.first, [State::Item.new(rule: @grammar.rules.first, position: 0)], states_created)
      enqueue_state(states, state)

      while (state = states.shift) do
        # Trace
        @tracer.trace_state(state)

        setup_state(state)

        # `State#transitions` can not be used here
        # because `items_to_state` of the `state` is not set yet.
        state._transitions.each do |next_sym, to_items|
          new_state, created = create_state(next_sym, to_items, states_created)
          state.set_items_to_state(to_items, new_state)
          state.set_lane_items(next_sym, new_state)
          enqueue_state(states, new_state) if created
        end
      end
    end

    # @rbs () -> Array[State::Action::Goto]
    def nterm_transitions
      a = []

      @states.each do |state|
        state.nterm_transitions.each do |goto|
          a << goto
        end
      end

      a
    end

    # @rbs () -> void
    def compute_look_ahead_sets
      report_duration(:compute_direct_read_sets) { compute_direct_read_sets }
      report_duration(:compute_reads_relation) { compute_reads_relation }
      report_duration(:compute_read_sets) { compute_read_sets }
      report_duration(:compute_includes_relation) { compute_includes_relation }
      report_duration(:compute_lookback_relation) { compute_lookback_relation }
      report_duration(:compute_follow_sets) { compute_follow_sets }
      report_duration(:compute_la) { compute_la }
    end

    # @rbs () -> void
    def compute_direct_read_sets
      @states.each do |state|
        state.nterm_transitions.each do |goto|
          ary = goto.to_state.term_transitions.map do |shift|
            shift.next_sym.number
          end

          @direct_read_sets[goto] = Bitmap.from_array(ary)
        end
      end
    end

    # @rbs () -> void
    def compute_reads_relation
      @states.each do |state|
        state.nterm_transitions.each do |goto|
          goto.to_state.nterm_transitions.each do |goto2|
            nterm2 = goto2.next_sym
            if nterm2.nullable
              @reads_relation[goto] ||= []
              @reads_relation[goto] << goto2
            end
          end
        end
      end
    end

    # @rbs () -> void
    def compute_read_sets
      @read_sets = Digraph.new(nterm_transitions, @reads_relation, @direct_read_sets).compute
    end

    # Execute transition of state by symbols
    # then return final state.
    #
    # @rbs (State state, Array[Grammar::Symbol] symbols) -> State
    def transition(state, symbols)
      symbols.each do |sym|
        state = state.transition(sym)
      end

      state
    end

    # @rbs () -> void
    def compute_includes_relation
      @states.each do |state|
        state.nterm_transitions.each do |goto|
          nterm = goto.next_sym
          @grammar.find_rules_by_symbol!(nterm).each do |rule|
            i = rule.rhs.count - 1

            while (i > -1) do
              sym = rule.rhs[i]

              break if sym.term?
              state2 = transition(state, rule.rhs[0...i])
              # p' = state, B = nterm, p = state2, A = sym
              key = state2.nterm_transitions.find do |goto2|
                goto2.next_sym.token_id == sym.token_id
              end || (raise "Goto by #{sym.name} on state #{state2.id} is not found")
              # TODO: need to omit if state == state2 ?
              @includes_relation[key] ||= []
              @includes_relation[key] << goto
              break unless sym.nullable
              i -= 1
            end
          end
        end
      end
    end

    # @rbs () -> void
    def compute_lookback_relation
      @states.each do |state|
        state.nterm_transitions.each do |goto|
          nterm = goto.next_sym
          @grammar.find_rules_by_symbol!(nterm).each do |rule|
            state2 = transition(state, rule.rhs)
            # p = state, A = nterm, q = state2, A -> ω = rule
            @lookback_relation[state2.id] ||= {}
            @lookback_relation[state2.id][rule.id] ||= []
            @lookback_relation[state2.id][rule.id] << goto
          end
        end
      end
    end

    # @rbs () -> void
    def compute_follow_sets
      @follow_sets = Digraph.new(nterm_transitions, @includes_relation, @read_sets).compute
    end

    # @rbs () -> void
    def compute_la
      @states.each do |state|
        lookback_relation_on_state = @lookback_relation[state.id]
        next unless lookback_relation_on_state
        rules.each do |rule|
          ary = lookback_relation_on_state[rule.id]
          next unless ary

          ary.each do |goto|
            # q = state, A -> ω = rule, p = state2, A = nterm
            follows = @follow_sets[goto]

            next if follows == 0

            @la[state.id] ||= {}
            @la[state.id][rule.id] ||= 0
            look_ahead = @la[state.id][rule.id] | follows
            @la[state.id][rule.id] |= look_ahead

            # No risk of conflict when
            # * the state only has single reduce
            # * the state only has nterm_transitions (GOTO)
            next if state.reduces.count == 1 && state.term_transitions.count == 0

            state.set_look_ahead(rule, bitmap_to_terms(look_ahead))
          end
        end
      end
    end

    # @rbs (Bitmap::bitmap bit) -> Array[Grammar::Symbol]
    def bitmap_to_terms(bit)
      ary = Bitmap.to_array(bit)
      ary.map do |i|
        @grammar.find_symbol_by_number!(i)
      end
    end

    # @rbs () -> void
    def compute_conflicts(lr_type)
      compute_shift_reduce_conflicts(lr_type)
      compute_reduce_reduce_conflicts
    end

    # @rbs () -> void
    def compute_shift_reduce_conflicts(lr_type)
      states.each do |state|
        state.term_transitions.each do |shift|
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
              resolved_conflict = State::ResolvedConflict.new(state: state, symbol: sym, reduce: reduce, which: :reduce, resolved_by_precedence: false)
              state.resolved_conflicts << resolved_conflict
              shift.not_selected = true
              mark_precedences_used(lr_type, shift_prec, reduce_prec, resolved_conflict)
              next
            when shift_prec > reduce_prec
              # Shift is selected
              resolved_conflict = State::ResolvedConflict.new(state: state, symbol: sym, reduce: reduce, which: :shift, resolved_by_precedence: false)
              state.resolved_conflicts << resolved_conflict
              reduce.add_not_selected_symbol(sym)
              mark_precedences_used(lr_type, shift_prec, reduce_prec, resolved_conflict)
              next
            end

            # shift_prec == reduce_prec, then check associativity
            case sym.precedence.type
            when :precedence
              # Can not resolve the conflict
              #
              # %precedence only specifies precedence and not specify associativity
              # then a conflict is unresolved if precedence is same.
              state.conflicts << State::ShiftReduceConflict.new(symbols: [sym], shift: shift, reduce: reduce)
              next
            when :right
              # Shift is selected
              resolved_conflict = State::ResolvedConflict.new(state: state, symbol: sym, reduce: reduce, which: :shift, resolved_by_precedence: true)
              state.resolved_conflicts << resolved_conflict
              reduce.add_not_selected_symbol(sym)
              mark_precedences_used(lr_type, shift_prec, reduce_prec, resolved_conflict)
              next
            when :left
              # Reduce is selected
              resolved_conflict = State::ResolvedConflict.new(state: state, symbol: sym, reduce: reduce, which: :reduce, resolved_by_precedence: true)
              state.resolved_conflicts << resolved_conflict
              shift.not_selected = true
              mark_precedences_used(lr_type, shift_prec, reduce_prec, resolved_conflict)
              next
            when :nonassoc
              # The conflict is resolved
              #
              # %nonassoc creates "run-time" error by removing both shift and reduce from
              # the state. This makes the state to get syntax error if the conflicted token appears.
              # On the other hand, %precedence creates "compile-time" error by keeping both
              # shift and reduce on the state. This makes the state to be conflicted on the token.
              #
              # https://www.gnu.org/software/bison/manual/html_node/Using-Precedence.html
              resolved_conflict = State::ResolvedConflict.new(state: state, symbol: sym, reduce: reduce, which: :error, resolved_by_precedence: false)
              state.resolved_conflicts << resolved_conflict
              shift.not_selected = true
              reduce.add_not_selected_symbol(sym)
              mark_precedences_used(lr_type, shift_prec, reduce_prec, resolved_conflict)
            else
              raise "Unknown precedence type. #{sym}"
            end
          end
        end
      end
    end

    # @rbs (Grammar::Precedence shift_prec, Grammar::Precedence reduce_prec, State::ResolvedConflict resolved_conflict) -> void
    def mark_precedences_used(lr_type, shift_prec, reduce_prec, resolved_conflict)
      case lr_type
      when :lalr
        shift_prec.mark_used_by_lalr(resolved_conflict)
        reduce_prec.mark_used_by_lalr(resolved_conflict)
      when :ielr
        shift_prec.mark_used_by_ielr(resolved_conflict)
        reduce_prec.mark_used_by_ielr(resolved_conflict)
      end
    end

    # @rbs () -> void
    def compute_reduce_reduce_conflicts
      states.each do |state|
        state.reduces.combination(2) do |reduce1, reduce2|
          next if reduce1.look_ahead.nil? || reduce2.look_ahead.nil?

          intersection = reduce1.look_ahead & reduce2.look_ahead

          unless intersection.empty?
            state.conflicts << State::ReduceReduceConflict.new(symbols: intersection, reduce1: reduce1, reduce2: reduce2)
          end
        end
      end
    end

    # @rbs () -> void
    def compute_default_reduction
      states.each do |state|
        next if state.reduces.empty?
        # Do not set, if conflict exist
        next unless state.conflicts.empty?
        # Do not set, if shift with `error` exists.
        next if state.term_transitions.map {|shift| shift.next_sym }.include?(@grammar.error_symbol)

        state.default_reduction_rule = state.reduces.map do |r|
          [r.rule, r.rule.id, (r.look_ahead || []).count]
        end.min_by do |rule, rule_id, count|
          [-count, rule_id]
        end.first
      end
    end

    # @rbs () -> void
    def clear_conflicts
      states.each(&:clear_conflicts)
    end

    # Definition 3.15 (Predecessors)
    #
    # @rbs () -> void
    def compute_predecessors
      @states.each do |state|
        state.transitions.each do |transition|
          transition.to_state.append_predecessor(state)
        end
      end
    end

    # Definition 3.16 (follow_kernel_items)
    #
    # @rbs () -> void
    def compute_follow_kernel_items
      set = nterm_transitions
      relation = compute_goto_internal_relation
      base_function = compute_goto_bitmaps
      Digraph.new(set, relation, base_function).compute.each do |goto, follow_kernel_items|
        state = goto.from_state
        state.follow_kernel_items[goto] = state.kernels.map {|kernel|
          [kernel, Bitmap.to_bool_array(follow_kernel_items, state.kernels.count)]
        }.to_h
      end
    end

    # @rbs () -> Hash[State::Action::Goto, Array[State::Action::Goto]]
    def compute_goto_internal_relation
      relations = {}

      @states.each do |state|
        state.nterm_transitions.each do |goto|
          relations[goto] = state.internal_dependencies(goto)
        end
      end

      relations
    end

    # @rbs () -> Hash[State::Action::Goto, Bitmap::bitmap]
    def compute_goto_bitmaps
      nterm_transitions.map {|goto|
        bools = goto.from_state.kernels.map.with_index {|kernel, i| i if kernel.next_sym == goto.next_sym && kernel.symbols_after_transition.all?(&:nullable) }.compact
        [goto, Bitmap.from_array(bools)]
      }.to_h
    end

    # Definition 3.20 (always_follows, one closure)
    #
    # @rbs () -> void
    def compute_always_follows
      set = nterm_transitions
      relation = compute_goto_successor_or_internal_relation
      base_function = compute_transition_bitmaps
      Digraph.new(set, relation, base_function).compute.each do |goto, always_follows_bitmap|
        goto.from_state.always_follows[goto] = bitmap_to_terms(always_follows_bitmap)
      end
    end

    # @rbs () -> Hash[State::Action::Goto, Array[State::Action::Goto]]
    def compute_goto_successor_or_internal_relation
      relations = {}

      @states.each do |state|
        state.nterm_transitions.each do |goto|
          relations[goto] = state.successor_dependencies(goto) + state.internal_dependencies(goto)
        end
      end

      relations
    end

    # @rbs () -> Hash[State::Action::Goto, Bitmap::bitmap]
    def compute_transition_bitmaps
      nterm_transitions.map {|goto|
        [goto, Bitmap.from_array(goto.to_state.term_transitions.map {|shift| shift.next_sym.number })]
      }.to_h
    end

    # Definition 3.24 (goto_follows, via always_follows)
    #
    # @rbs () -> void
    def compute_goto_follows
      set = nterm_transitions
      relation = compute_goto_internal_or_predecessor_dependencies
      base_function = compute_always_follows_bitmaps
      Digraph.new(set, relation, base_function).compute.each do |goto, goto_follows_bitmap|
        goto.from_state.goto_follows[goto] = bitmap_to_terms(goto_follows_bitmap)
      end
    end

    # @rbs () -> Hash[State::Action::Goto, Array[State::Action::Goto]]
    def compute_goto_internal_or_predecessor_dependencies
      relations = {}

      @states.each do |state|
        state.nterm_transitions.each do |goto|
          relations[goto] = state.internal_dependencies(goto) + state.predecessor_dependencies(goto)
        end
      end

      relations
    end

    # @rbs () -> Hash[State::Action::Goto, Bitmap::bitmap]
    def compute_always_follows_bitmaps
      nterm_transitions.map {|goto|
        [goto, Bitmap.from_array(goto.from_state.always_follows[goto].map(&:number))]
      }.to_h
    end

    # @rbs () -> void
    def split_states
      @states.each do |state|
        state.transitions.each do |transition|
          compute_state(state, transition, transition.to_state)
        end
      end
    end

    # @rbs () -> void
    def compute_inadequacy_annotations
      @states.each do |state|
        state.annotate_manifestation
      end

      queue = @states.reject {|state| state.annotation_list.empty? }

      while (curr = queue.shift) do
        curr.predecessors.each do |pred|
          cache = pred.annotation_list.dup
          curr.annotate_predecessor(pred)
          queue << pred if cache != pred.annotation_list && !queue.include?(pred)
        end
      end
    end

    # @rbs (State state, State::lookahead_set filtered_lookaheads) -> void
    def merge_lookaheads(state, filtered_lookaheads)
      return if state.kernels.all? {|item| (filtered_lookaheads[item] - state.item_lookahead_set[item]).empty? }

      state.item_lookahead_set = state.item_lookahead_set.merge {|_, v1, v2| v1 | v2 }
      state.transitions.each do |transition|
        next if transition.to_state.lookaheads_recomputed
        compute_state(state, transition, transition.to_state)
      end
    end

    # @rbs (State state, State::Action::Shift | State::Action::Goto transition, State next_state) -> void
    def compute_state(state, transition, next_state)
      propagating_lookaheads = state.propagate_lookaheads(next_state)
      s = next_state.ielr_isocores.find {|st| st.is_compatible?(propagating_lookaheads) }

      if s.nil?
        s = next_state.lalr_isocore
        new_state = State.new(@states.count, s.accessing_symbol, s.kernels)
        new_state.closure = s.closure
        new_state.compute_transitions_and_reduces
        s.transitions.each do |transition|
          new_state.set_items_to_state(transition.to_items, transition.to_state)
        end
        @states << new_state
        new_state.lalr_isocore = s
        s.ielr_isocores << new_state
        s.ielr_isocores.each do |st|
          st.ielr_isocores = s.ielr_isocores
        end
        new_state.lookaheads_recomputed = true
        new_state.item_lookahead_set = propagating_lookaheads
        state.update_transition(transition, new_state)
      elsif(!s.lookaheads_recomputed)
        s.lookaheads_recomputed = true
        s.item_lookahead_set = propagating_lookaheads
      else
        merge_lookaheads(s, propagating_lookaheads)
        state.update_transition(transition, s) if state.items_to_state[transition.to_items].id != s.id
      end
    end

    # @rbs (Logger logger) -> void
    def validate_conflicts_within_threshold!(logger)
      exit false unless conflicts_within_threshold?(logger)
    end

    # @rbs (Logger logger) -> bool
    def conflicts_within_threshold?(logger)
      return true unless @grammar.expect

      [sr_conflicts_within_threshold?(logger), rr_conflicts_within_threshold?(logger)].all?
    end

    # @rbs (Logger logger) -> bool
    def sr_conflicts_within_threshold?(logger)
      return true if @grammar.expect == sr_conflicts_count

      logger.error("shift/reduce conflicts: #{sr_conflicts_count} found, #{@grammar.expect} expected")
      false
    end

    # @rbs (Logger logger) -> bool
    def rr_conflicts_within_threshold?(logger, expected: 0)
      return true if expected == rr_conflicts_count

      logger.error("reduce/reduce conflicts: #{rr_conflicts_count} found, #{expected} expected")
      false
    end

    # @rbs () -> void
    def clear_look_ahead_sets
      @direct_read_sets.clear
      @reads_relation.clear
      @read_sets.clear
      @includes_relation.clear
      @lookback_relation.clear
      @follow_sets.clear
      @la.clear

      @_direct_read_sets = nil
      @_read_sets = nil
      @_follow_sets = nil
      @_la = nil
    end
  end
end
