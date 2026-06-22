# rbs_inline: enabled
# frozen_string_literal: true

require "set"
require "timeout"

require_relative "counterexamples/derivation"
require_relative "counterexamples/example"
require_relative "counterexamples/node"
require_relative "counterexamples/path"
require_relative "counterexamples/state_item"
require_relative "counterexamples/triple"

module Lrama
  # See: https://www.cs.cornell.edu/andru/papers/cupex/cupex.pdf
  #      4. Constructing Nonunifying Counterexamples
  class Counterexamples
    PathSearchTimeLimit = 10 # 10 sec
    CumulativeTimeLimit = 120 # 120 sec

    # @rbs!
    #   @states: States
    #   @iterate_count: Integer
    #   @total_duration: Float
    #   @exceed_cumulative_time_limit: bool
    #   @state_items: Hash[[State, State::Item], StateItem]
    #   @triples: Hash[Integer, Triple]
    #   @transitions: Hash[[StateItem, Grammar::Symbol], StateItem]
    #   @reverse_transitions: Hash[[StateItem, Grammar::Symbol], Set[StateItem]]
    #   @productions: Hash[StateItem, Set[StateItem]]
    #   @reverse_productions: Hash[[State, Grammar::Symbol], Set[StateItem]] # Grammar::Symbol is nterm
    #   @state_item_shift: Integer

    attr_reader :transitions #: Hash[[StateItem, Grammar::Symbol], StateItem]
    attr_reader :productions #: Hash[StateItem, Set[StateItem]]

    # @rbs (States states) -> void
    def initialize(states)
      @states = states
      @iterate_count = 0
      @total_duration = 0
      @exceed_cumulative_time_limit = false
      @triples = {}
      setup_state_items
      setup_transitions
      setup_productions
    end

    # @rbs () -> "#<Counterexamples>"
    def to_s
      "#<Counterexamples>"
    end
    alias :inspect :to_s

    # @rbs (State conflict_state) -> Array[Example]
    def compute(conflict_state)
      conflict_state.conflicts.flat_map do |conflict|
        # Check cumulative time limit for not each path search method call but each conflict
        # to avoid one of example's path to be nil.
        next if @exceed_cumulative_time_limit

        case conflict.type
        when :shift_reduce
          # @type var conflict: State::ShiftReduceConflict
          shift_reduce_example(conflict_state, conflict)
        when :reduce_reduce
          # @type var conflict: State::ReduceReduceConflict
          reduce_reduce_examples(conflict_state, conflict)
        end
      rescue Timeout::Error => e
        STDERR.puts "Counterexamples calculation for state #{conflict_state.id} #{e.message} with #{@iterate_count} iteration"
        increment_total_duration(PathSearchTimeLimit)
        nil
      end.compact
    end

    private

    # @rbs (State state, State::Item item) -> StateItem
    def get_state_item(state, item)
      @state_items[[state, item]]
    end

    # For optimization, create all StateItem in advance
    # and use them by fetching an instance from `@state_items`.
    # Do not create new StateItem instance in the shortest path search process
    # to avoid miss hash lookup.
    #
    # @rbs () -> void
    def setup_state_items
      @state_items = {}
      count = 0

      @states.states.each do |state|
        state.items.each do |item|
          @state_items[[state, item]] = StateItem.new(count, state, item)
          count += 1
        end
      end

      @state_item_shift = Math.log(count, 2).ceil
    end

    # @rbs () -> void
    def setup_transitions
      @transitions = {}
      @reverse_transitions = {}

      @states.states.each do |src_state|
        trans = {} #: Hash[Grammar::Symbol, State]

        src_state.transitions.each do |transition|
          trans[transition.next_sym] = transition.to_state
        end

        src_state.items.each do |src_item|
          next if src_item.end_of_rule?
          sym = src_item.next_sym
          dest_state = trans[sym]

          dest_state.kernels.each do |dest_item|
            next unless (src_item.rule == dest_item.rule) && (src_item.position + 1 == dest_item.position)
            src_state_item = get_state_item(src_state, src_item)
            dest_state_item = get_state_item(dest_state, dest_item)

            @transitions[[src_state_item, sym]] = dest_state_item

            # @type var key: [StateItem, Grammar::Symbol]
            key = [dest_state_item, sym]
            @reverse_transitions[key] ||= Set.new
            @reverse_transitions[key] << src_state_item
          end
        end
      end
    end

    # @rbs () -> void
    def setup_productions
      @productions = {}
      @reverse_productions = {}

      @states.states.each do |state|
        # Grammar::Symbol is LHS
        h = {} #: Hash[Grammar::Symbol, Set[StateItem]]

        state.closure.each do |item|
          sym = item.lhs

          h[sym] ||= Set.new
          h[sym] << get_state_item(state, item)
        end

        state.items.each do |item|
          next if item.end_of_rule?
          next if item.next_sym.term?

          sym = item.next_sym
          state_item = get_state_item(state, item)
          @productions[state_item] = h[sym]

          # @type var key: [State, Grammar::Symbol]
          key = [state, sym]
          @reverse_productions[key] ||= Set.new
          @reverse_productions[key] << state_item
        end
      end
    end

    # For optimization, use same Triple if it's already created.
    # Do not create new Triple instance anywhere else
    # to avoid miss hash lookup.
    #
    # @rbs (StateItem state_item, Bitmap::bitmap precise_lookahead_set) -> Triple
    def get_triple(state_item, precise_lookahead_set)
      key = (precise_lookahead_set << @state_item_shift) | state_item.id
      @triples[key] ||= Triple.new(state_item, precise_lookahead_set)
    end

    # @rbs (State conflict_state, State::ShiftReduceConflict conflict) -> Example
    def shift_reduce_example(conflict_state, conflict)
      conflict_symbol = conflict.symbols.first
      # @type var shift_conflict_item: ::Lrama::State::Item
      shift_conflict_item = conflict_state.items.find { |item| item.next_sym == conflict_symbol }
      path2 = with_timeout("#shortest_path:") do
        shortest_path(conflict_state, conflict.reduce.item, conflict_symbol)
      end
      path1 = with_timeout("#find_shift_conflict_shortest_path:") do
        find_shift_conflict_shortest_path(path2, conflict_state, shift_conflict_item)
      end

      Example.new(path1, path2, conflict, conflict_symbol, self)
    end

    # @rbs (State conflict_state, State::ReduceReduceConflict conflict) -> Example
    def reduce_reduce_examples(conflict_state, conflict)
      conflict_symbol = conflict.symbols.first
      path1 = with_timeout("#shortest_path:") do
        shortest_path(conflict_state, conflict.reduce1.item, conflict_symbol)
      end
      path2 = with_timeout("#shortest_path:") do
        shortest_path(conflict_state, conflict.reduce2.item, conflict_symbol)
      end

      Example.new(path1, path2, conflict, conflict_symbol, self)
    end

    # @rbs (Array[StateItem]? reduce_state_items, State conflict_state, State::Item conflict_item) -> Array[StateItem]
    def find_shift_conflict_shortest_path(reduce_state_items, conflict_state, conflict_item)
      time1 = Time.now.to_f
      @iterate_count = 0

      target_state_item = get_state_item(conflict_state, conflict_item)
      result = [target_state_item]
      reversed_state_items = reduce_state_items.to_a.reverse
      # Index for state_item
      i = 0

      while (state_item = reversed_state_items[i])
        # Index for prev_state_item
        j = i + 1
        _j = j

        while (prev_state_item = reversed_state_items[j])
          if prev_state_item.type == :production
            j += 1
          else
            break
          end
        end

        if target_state_item == state_item || target_state_item.item.start_item?
          result.concat(
            reversed_state_items[_j..-1] #: Array[StateItem]
          )
          break
        end

        if target_state_item.type == :production
          queue = [] #: Array[Node[StateItem]]
          queue << Node.new(target_state_item, nil)

          # Find reverse production
          while (sis = queue.shift)
            @iterate_count += 1
            si = sis.elem

            # Reach to start state
            if si.item.start_item?
              a = Node.to_a(sis).reverse
              a.shift
              result.concat(a)
              target_state_item = si
              break
            end

            if si.type == :production
              # @type var key: [State, Grammar::Symbol]
              key = [si.state, si.item.lhs]
              @reverse_productions[key].each do |state_item|
                queue << Node.new(state_item, sis)
              end
            else
              # @type var key: [StateItem, Grammar::Symbol]
              key = [si, si.item.previous_sym]
              @reverse_transitions[key].each do |prev_target_state_item|
                next if prev_target_state_item.state != prev_state_item&.state
                a = Node.to_a(sis).reverse
                a.shift
                result.concat(a)
                result << prev_target_state_item
                target_state_item = prev_target_state_item
                i = j
                queue.clear
                break
              end
            end
          end
        else
          # Find reverse transition
          # @type var key: [StateItem, Grammar::Symbol]
          key = [target_state_item, target_state_item.item.previous_sym]
          @reverse_transitions[key].each do |prev_target_state_item|
            next if prev_target_state_item.state != prev_state_item&.state
            result << prev_target_state_item
            target_state_item = prev_target_state_item
            i = j
            break
          end
        end
      end

      time2 = Time.now.to_f
      duration = time2 - time1
      increment_total_duration(duration)

      if Tracer::Duration.enabled?
        STDERR.puts sprintf("  %s %10.5f s", "find_shift_conflict_shortest_path #{@iterate_count} iteration", duration)
      end

      result.reverse
    end

    # @rbs (StateItem target) -> Set[StateItem]
    def reachable_state_items(target)
      result = Set.new
      queue = [target]

      while (state_item = queue.shift)
        next if result.include?(state_item)
        result << state_item

        @reverse_transitions[[state_item, state_item.item.previous_sym]]&.each do |prev_state_item|
          queue << prev_state_item
        end

        if state_item.item.beginning_of_rule?
          @reverse_productions[[state_item.state, state_item.item.lhs]]&.each do |si|
            queue << si
          end
        end
      end

      result
    end

    # @rbs (State conflict_state, State::Item conflict_reduce_item, Grammar::Symbol conflict_term) -> ::Array[StateItem]?
    def shortest_path(conflict_state, conflict_reduce_item, conflict_term)
      time1 = Time.now.to_f
      @iterate_count = 0

      queue = [] #: Array[[Triple, Path]]
      visited = {} #: Hash[Triple, true]
      start_state = @states.states.first #: Lrama::State
      conflict_term_bit = Bitmap::from_integer(conflict_term.number)
      raise "BUG: Start state should be just one kernel." if start_state.kernels.count != 1
      reachable = reachable_state_items(get_state_item(conflict_state, conflict_reduce_item))
      start = get_triple(get_state_item(start_state, start_state.kernels.first), Bitmap::from_integer(@states.eof_symbol.number))

      queue << [start, Path.new(start.state_item, nil)]

      while (triple, path = queue.shift)
        @iterate_count += 1

        # Found
        if (triple.state == conflict_state) && (triple.item == conflict_reduce_item) && (triple.l & conflict_term_bit != 0)
          state_items = [path.state_item]

          while (path = path.parent)
            state_items << path.state_item
          end

          time2 = Time.now.to_f
          duration = time2 - time1
          increment_total_duration(duration)

          if Tracer::Duration.enabled?
            STDERR.puts sprintf("  %s %10.5f s", "shortest_path #{@iterate_count} iteration", duration)
          end

          return state_items.reverse
        end

        # transition
        next_state_item = @transitions[[triple.state_item, triple.item.next_sym]]
        if next_state_item && reachable.include?(next_state_item)
          # @type var t: Triple
          t = get_triple(next_state_item, triple.l)
          unless visited[t]
            visited[t] = true
            queue << [t, Path.new(t.state_item, path)]
          end
        end

        # production step
        @productions[triple.state_item]&.each do |si|
          next unless reachable.include?(si)

          l = follow_l(triple.item, triple.l)
          # @type var t: Triple
          t = get_triple(si, l)
          unless visited[t]
            visited[t] = true
            queue << [t, Path.new(t.state_item, path)]
          end
        end
      end

      return nil
    end

    # @rbs (State::Item item, Bitmap::bitmap current_l) -> Bitmap::bitmap
    def follow_l(item, current_l)
      # 1. follow_L (A -> X1 ... Xn-1 • Xn) = L
      # 2. follow_L (A -> X1 ... Xk • Xk+1 Xk+2 ... Xn) = {Xk+2} if Xk+2 is a terminal
      # 3. follow_L (A -> X1 ... Xk • Xk+1 Xk+2 ... Xn) = FIRST(Xk+2) if Xk+2 is a nonnullable nonterminal
      # 4. follow_L (A -> X1 ... Xk • Xk+1 Xk+2 ... Xn) = FIRST(Xk+2) + follow_L (A -> X1 ... Xk+1 • Xk+2 ... Xn) if Xk+2 is a nullable nonterminal
      case
      when item.number_of_rest_symbols == 1
        current_l
      when item.next_next_sym.term?
        item.next_next_sym.number_bitmap
      when !item.next_next_sym.nullable
        item.next_next_sym.first_set_bitmap
      else
        item.next_next_sym.first_set_bitmap | follow_l(item.new_by_next_position, current_l)
      end
    end

    # @rbs [T] (String message) { -> T } -> T
    def with_timeout(message)
      Timeout.timeout(PathSearchTimeLimit, Timeout::Error, message + " timeout of #{PathSearchTimeLimit} sec exceeded") do
        yield
      end
    end

    # @rbs (Float|Integer duration) -> void
    def increment_total_duration(duration)
      @total_duration += duration

      if !@exceed_cumulative_time_limit && @total_duration > CumulativeTimeLimit
        @exceed_cumulative_time_limit = true
        STDERR.puts "CumulativeTimeLimit #{CumulativeTimeLimit} sec exceeded then skip following Counterexamples calculation"
      end
    end
  end
end
