require "forwardable"
require "lrama/report"

module Lrama
  class State
    class Reduce
      # https://www.gnu.org/software/bison/manual/html_node/Default-Reductions.html
      attr_reader :item, :look_ahead, :not_selected_symbols
      attr_accessor :default_reduction

      def initialize(item)
        @item = item
        @look_ahead = nil
        @not_selected_symbols = []
      end

      def rule
        @item.rule
      end

      def look_ahead=(look_ahead)
        @look_ahead = look_ahead.freeze
      end

      def add_not_selected_symbol(sym)
        @not_selected_symbols << sym
      end

      def selected_look_ahead
        if @look_ahead
          @look_ahead - @not_selected_symbols
        else
          []
        end
      end
    end

    class Shift
      attr_reader :next_sym, :next_items
      attr_accessor :not_selected

      def initialize(next_sym, next_items)
        @next_sym = next_sym
        @next_items = next_items
      end
    end

    # * symbol: A symbol under discussion
    # * reduce: A reduce under discussion
    # * which: For which a conflict is resolved. :shift, :reduce or :error (for nonassociative)
    ResolvedConflict = Struct.new(:symbol, :reduce, :which, :same_prec, keyword_init: true) do
      def report_message
        s = symbol.display_name
        r = reduce.rule.precedence_sym.display_name
        case
        when which == :shift && same_prec
          msg = "resolved as #{which} (%right #{s})"
        when which == :shift
          msg = "resolved as #{which} (#{r} < #{s})"
        when which == :reduce && same_prec
          msg = "resolved as #{which} (%left #{s})"
        when which == :reduce
          msg = "resolved as #{which} (#{s} < #{r})"
        when which == :error
          msg = "resolved as an #{which} (%nonassoc #{s})"
        else
          raise "Unknown direction. #{self}"
        end

        "Conflict between rule #{reduce.rule.id} and token #{s} #{msg}."
      end
    end

    Conflict = Struct.new(:symbols, :reduce, :type, keyword_init: true)

    attr_reader :id, :accessing_symbol, :kernels, :conflicts, :resolved_conflicts,
                :default_reduction_rule, :closure, :items
    attr_accessor :shifts, :reduces

    def initialize(id, accessing_symbol, kernels)
      @id = id
      @accessing_symbol = accessing_symbol
      @kernels = kernels.freeze
      @items = @kernels
      # Manage relationships between items to state
      # to resolve next state
      @items_to_state = {}
      @conflicts = []
      @resolved_conflicts = []
      @default_reduction_rule = nil
    end

    def closure=(closure)
      @closure = closure
      @items = @kernels + @closure
    end

    def non_default_reduces
      reduces.select do |reduce|
        reduce.rule != @default_reduction_rule
      end
    end

    def compute_shifts_reduces
      _shifts = {}
      reduces = []
      items.each do |item|
        # TODO: Consider what should be pushed
        if item.end_of_rule?
          reduces << Reduce.new(item)
        else
          key = item.next_sym
          _shifts[key] ||= []
          _shifts[key] << item.new_by_next_position
        end
      end

      # It seems Bison 3.8.2 iterates transitions order by symbol number
      shifts = _shifts.sort_by do |next_sym, new_items|
        next_sym.number
      end.map do |next_sym, new_items|
        Shift.new(next_sym, new_items.flatten)
      end
      self.shifts = shifts.freeze
      self.reduces = reduces.freeze
    end

    def set_items_to_state(items, next_state)
      @items_to_state[items] = next_state
    end

    #
    def set_look_ahead(rule, look_ahead)
      reduce = reduces.find do |r|
        r.rule == rule
      end

      reduce.look_ahead = look_ahead
    end

    # Returns array of [nterm, next_state]
    def nterm_transitions
      return @nterm_transitions if @nterm_transitions

      @nterm_transitions = []

      shifts.each do |shift|
        next if shift.next_sym.term?

        @nterm_transitions << [shift, @items_to_state[shift.next_items]]
      end

      @nterm_transitions
    end

    # Returns array of [term, next_state]
    def term_transitions
      return @term_transitions if @term_transitions

      @term_transitions = []

      shifts.each do |shift|
        next if shift.next_sym.nterm?

        @term_transitions << [shift, @items_to_state[shift.next_items]]
      end

      @term_transitions
    end

    def selected_term_transitions
      term_transitions.select do |shift, next_state|
        !shift.not_selected
      end
    end

    # Move to next state by sym
    def transition(sym)
      result = nil

      if sym.term?
        term_transitions.each do |shift, next_state|
          term = shift.next_sym
          result = next_state if term == sym
        end
      else
        nterm_transitions.each do |shift, next_state|
          nterm = shift.next_sym
          result = next_state if nterm == sym
        end
      end

      raise "Can not transit by #{sym} #{self}" if result.nil?

      result
    end

    def find_reduce_by_item!(item)
      reduces.find do |r|
        r.item == item
      end || (raise "reduce is not found. #{item}, #{state}")
    end

    def default_reduction_rule=(default_reduction_rule)
      @default_reduction_rule = default_reduction_rule

      reduces.each do |r|
        if r.rule == default_reduction_rule
          r.default_reduction = true
        end
      end
    end

    def sr_conflicts
      @conflicts.select do |conflict|
        conflict.type == :shift_reduce
      end
    end

    def rr_conflicts
      @conflicts.select do |conflict|
        conflict.type == :reduce_reduce
      end
    end
  end

  # States is passed to a template file
  #
  # "Efficient Computation of LALR(1) Look-Ahead Sets"
  #   https://dl.acm.org/doi/pdf/10.1145/69622.357187
  class States
    extend Forwardable
    include Lrama::Report::Duration

    def_delegators "@grammar", :symbols, :terms, :nterms, :rules,
      :accept_symbol, :eof_symbol, :find_symbol_by_s_value!

    # TODO: Validate position is not over rule rhs
    Item = Struct.new(:rule, :position, keyword_init: true) do
      # Optimization for States#setup_state
      def hash
        [rule.id, position].hash
      end

      def rule_id
        rule.id
      end

      def next_sym
        rule.rhs[position]
      end

      def end_of_rule?
        rule.rhs.count == position
      end

      def new_by_next_position
        Item.new(rule: rule, position: position + 1)
      end

      def previous_sym
        rule.rhs[position - 1]
      end

      def display_name
        r = rule.rhs.map(&:display_name).insert(position, "•").join(" ")
        "#{r}  (rule #{rule.id})"
      end

      # Right after position
      def display_rest
        r = rule.rhs[position..-1].map(&:display_name).join(" ")
        ". #{r}  (rule #{rule.id})"
      end
    end

    attr_reader :states, :reads_relation, :includes_relation, :lookback_relation

    def initialize(grammar, warning, trace_state: false)
      @grammar = grammar
      @warning = warning
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

      check_conflicts
    end

    def reporter
      StatesReporter.new(self)
    end

    def states_count
      @states.count
    end

    def direct_read_sets
      h = {}

      @direct_read_sets.each do |k, v|
        h[k] = bitmap_to_terms(v)
      end

      return h
    end

    def read_sets
      h = {}

      @read_sets.each do |k, v|
        h[k] = bitmap_to_terms(v)
      end

      return h
    end

    def follow_sets
      h = {}

      @follow_sets.each do |k, v|
        h[k] = bitmap_to_terms(v)
      end

      return h
    end

    def la
      h = {}

      @la.each do |k, v|
        h[k] = bitmap_to_terms(v)
      end

      return h
    end

    private

    def sr_conflicts
      @states.flat_map(&:sr_conflicts)
    end

    def rr_conflicts
      @states.flat_map(&:rr_conflicts)
    end

    def initial_attrs
      h = {}

      attrs.each do |attr|
        h[attr.id] = false
      end

      h
    end

    def trace_state
      if @trace_state
        yield STDERR
      end
    end

    def create_state(accessing_symbol, kernels, states_creted)
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
      return [states_creted[kernels], false] if states_creted[kernels]

      state = State.new(@states.count, accessing_symbol, kernels)
      @states << state
      states_creted[kernels] = state

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
        out << sprintf("state_list_append (state = %d, symbol = %d (%s))",
          @states.count, previous.number, previous.display_name)
      end

      states << state
    end

    def compute_lr0_states
      # State queue
      states = []
      states_creted = {}

      state, _ = create_state(symbols.first, [Item.new(rule: @grammar.rules.first, position: 0)], states_creted)
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
          new_state, created = create_state(shift.next_sym, shift.next_items, states_creted)
          state.set_items_to_state(shift.next_items, new_state)
          enqueue_state(states, new_state) if created
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
              break if !sym.nullable
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
          next if !ary

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
            next if !reduce.look_ahead.include?(sym)

            # Shift/Reduce conflict
            shift_prec = sym.precedence
            reduce_prec = reduce.item.rule.precedence

            # Can resolve only when both have prec
            unless shift_prec && reduce_prec
              state.conflicts << State::Conflict.new(symbols: [sym], reduce: reduce, type: :shift_reduce)
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
        a = []

        state.reduces.each do |reduce|
          next if reduce.look_ahead.nil?

          intersection = a & reduce.look_ahead
          a += reduce.look_ahead

          if !intersection.empty?
            state.conflicts << State::Conflict.new(symbols: intersection.dup, reduce: reduce, type: :reduce_reduce)
          end
        end
      end
    end

    def compute_default_reduction
      states.each do |state|
        next if state.reduces.empty?
        # Do not set, if conflict exist
        next if !state.conflicts.empty?
        # Do not set, if shift with `error` exists.
        next if state.shifts.map(&:next_sym).include?(@grammar.error_symbol)

        state.default_reduction_rule = state.reduces.map do |r|
          [r.rule, r.rule.id, (r.look_ahead || []).count]
        end.sort_by do |rule, rule_id, count|
          [-count, rule_id]
        end.first.first
      end
    end

    def check_conflicts
      sr_count = sr_conflicts.count
      rr_count = rr_conflicts.count

      if @grammar.expect

        expected_sr_conflicts = @grammar.expect
        expected_rr_conflicts = 0

        if expected_sr_conflicts != sr_count
          @warning.error("shift/reduce conflicts: #{sr_count} found, #{expected_sr_conflicts} expected")
        end

        if expected_rr_conflicts != rr_count
          @warning.error("reduce/reduce conflicts: #{rr_count} found, #{expected_rr_conflicts} expected")
        end
      else
        if sr_count != 0
          @warning.warn("shift/reduce conflicts: #{sr_count} found")
        end

        if rr_count != 0
          @warning.warn("reduce/reduce conflicts: #{rr_count} found")
        end
      end
    end
  end
end
