# frozen_string_literal: true

require_relative "state/reduce"
require_relative "state/reduce_reduce_conflict"
require_relative "state/resolved_conflict"
require_relative "state/shift"
require_relative "state/shift_reduce_conflict"

module Lrama
  class State
    attr_reader :id, :accessing_symbol, :kernels, :conflicts, :resolved_conflicts,
                :default_reduction_rule, :closure, :items
    attr_accessor :shifts, :reduces, :ielr_isocores, :lalr_isocore

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
      @predecessors = []
      @lalr_isocore = self
      @ielr_isocores = [self]
      @internal_dependencies = {}
      @successor_dependencies = {}
      @always_follows = {}
    end

    def closure=(closure)
      @closure = closure
      @items = @kernels + @closure
    end

    def non_default_reduces
      reduces.reject do |reduce|
        reduce.rule == @default_reduction_rule
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

    def set_look_ahead(rule, look_ahead)
      reduce = reduces.find do |r|
        r.rule == rule
      end

      reduce.look_ahead = look_ahead
    end

    def nterm_transitions
      @nterm_transitions ||= transitions.select {|shift, _| shift.next_sym.nterm? }
    end

    def term_transitions
      @term_transitions ||= transitions.select {|shift, _| shift.next_sym.term? }
    end

    def transitions
      @transitions ||= shifts.map {|shift| [shift, @items_to_state[shift.next_items]] }
    end

    def update_transition(shift, next_state)
      set_items_to_state(shift.next_items, next_state)
      next_state.append_predecessor(self)
      clear_transitions_cache
    end

    def clear_transitions_cache
      @nterm_transitions = nil
      @term_transitions = nil
      @transitions = nil
    end

    def selected_term_transitions
      term_transitions.reject do |shift, next_state|
        shift.not_selected
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
      end || (raise "reduce is not found. #{item}")
    end

    def default_reduction_rule=(default_reduction_rule)
      @default_reduction_rule = default_reduction_rule

      reduces.each do |r|
        if r.rule == default_reduction_rule
          r.default_reduction = true
        end
      end
    end

    def has_conflicts?
      !@conflicts.empty?
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

    def propagate_lookaheads(next_state)
      next_state.kernels.map {|item|
        lookahead_sets =
          if item.position == 1
            goto_follow_set(item.lhs)
          else
            kernel = kernels.find {|k| k.predecessor_item_of?(item) }
            item_lookahead_set[kernel]
          end

        [item, lookahead_sets & next_state.lookahead_set_filters[item]]
      }.to_h
    end

    def lookaheads_recomputed
      !@item_lookahead_set.nil?
    end

    def compatible_lookahead?(filtered_lookahead)
      !lookaheads_recomputed ||
        @lalr_isocore.annotation_list.all? {|token, actions|
          a = dominant_contribution(token, actions, item_lookahead_set)
          b = dominant_contribution(token, actions, filtered_lookahead)
          a.nil? || b.nil? || a == b
        }
    end

    def lookahead_set_filters
      kernels.map {|kernel|
        [kernel,
         @lalr_isocore.annotation_list.select {|token, actions|
           token.term? && actions.any? {|action, contributions|
             !contributions.nil? && contributions.key?(kernel) && contributions[kernel]
           }
         }.map {|token, _| token }
        ]
      }.to_h
    end

    def dominant_contribution(token, actions, lookaheads)
      a = actions.select {|action, contributions|
        contributions.nil? || contributions.any? {|item, contributed| contributed && lookaheads[item].include?(token) }
      }.map {|action, _| action }
      return nil if a.empty?
      a.reject {|action|
        if action.is_a?(State::Shift)
          action.not_selected
        elsif action.is_a?(State::Reduce)
          action.not_selected_symbols.include?(token)
        end
      }
    end

    def inadequacy_list
      return @inadequacy_list if @inadequacy_list

      shift_contributions = shifts.map {|shift|
        [shift.next_sym, [shift]]
      }.to_h
      reduce_contributions = reduces.map {|reduce|
        (reduce.look_ahead || []).map {|sym|
          [sym, [reduce]]
        }.to_h
      }.reduce(Hash.new([])) {|hash, cont|
        hash.merge(cont) {|_, a, b| a | b }
      }

      list = shift_contributions.merge(reduce_contributions) {|_, a, b| a | b }
      @inadequacy_list = list.select {|token, actions| token.term? && actions.size > 1 }
    end

    def annotation_list
      return @annotation_list if @annotation_list

      @annotation_list = annotate_manifestation
      @annotation_list = @items_to_state.values.map {|next_state| next_state.annotate_predecessor(self) }
        .reduce(@annotation_list) {|result, annotations|
          result.merge(annotations) {|_, actions_a, actions_b|
            if actions_a.nil? || actions_b.nil?
              actions_a || actions_b
            else
              actions_a.merge(actions_b) {|_, contributions_a, contributions_b|
                if contributions_a.nil? || contributions_b.nil?
                  next contributions_a || contributions_b
                end

                contributions_a.merge(contributions_b) {|_, contributed_a, contributed_b|
                  contributed_a || contributed_b
                }
              }
            end
          }
        }
    end

    def annotate_manifestation
      inadequacy_list.transform_values {|actions|
        actions.map {|action|
          if action.is_a?(Shift)
            [action, nil]
          elsif action.is_a?(Reduce)
            if action.rule.empty_rule?
              [action, lhs_contributions(action.rule.lhs, inadequacy_list.key(actions))]
            else
              contributions = kernels.map {|kernel| [kernel, kernel.rule == action.rule && kernel.end_of_rule?] }.to_h
              [action, contributions]
            end
          end
        }.to_h
      }
    end

    def annotate_predecessor(predecessor)
      annotation_list.transform_values {|actions|
        token = annotation_list.key(actions)
        actions.transform_values {|inadequacy|
          next nil if inadequacy.nil?
          lhs_adequacy = kernels.any? {|kernel|
            inadequacy[kernel] && kernel.position == 1 && predecessor.lhs_contributions(kernel.lhs, token).nil?
          }
          if lhs_adequacy
            next nil
          else
            predecessor.kernels.map {|pred_k|
              [pred_k, kernels.any? {|k|
                inadequacy[k] && (
                  pred_k.predecessor_item_of?(k) && predecessor.item_lookahead_set[pred_k].include?(token) ||
                  k.position == 1 && predecessor.lhs_contributions(k.lhs, token)[pred_k]
                )
              }]
            }.to_h
          end
        }
      }
    end

    def lhs_contributions(sym, token)
      shift, next_state = nterm_transitions.find {|sh, _| sh.next_sym == sym }
      if always_follows(shift, next_state).include?(token)
        nil
      else
        kernels.map {|kernel| [kernel, follow_kernel_items(shift, next_state, kernel) && item_lookahead_set[kernel].include?(token)] }.to_h
      end
    end

    def follow_kernel_items(shift, next_state, kernel)
      queue = [[self, shift, next_state]]
      until queue.empty?
        st, sh, next_st = queue.pop
        return true if kernel.next_sym == sh.next_sym && kernel.symbols_after_transition.all?(&:nullable)
        st.internal_dependencies(sh, next_st).each {|v| queue << v }
      end
      false
    end

    def item_lookahead_set
      return @item_lookahead_set if @item_lookahead_set

      kernels.map {|item|
        value =
          if item.lhs.accept_symbol?
            []
          elsif item.position > 1
            prev_items = predecessors_with_item(item)
            prev_items.map {|st, i| st.item_lookahead_set[i] }.reduce([]) {|acc, syms| acc |= syms }
          elsif item.position == 1
            prev_state = @predecessors.find {|p| p.shifts.any? {|shift| shift.next_sym == item.lhs } }
            shift, next_state = prev_state.nterm_transitions.find {|shift, _| shift.next_sym == item.lhs }
            prev_state.goto_follows(shift, next_state)
          end
        [item, value]
      }.to_h
    end

    def item_lookahead_set=(k)
      @item_lookahead_set = k
    end

    def predecessors_with_item(item)
      result = []
      @predecessors.each do |pre|
        pre.items.each do |i|
          result << [pre, i] if i.predecessor_item_of?(item)
        end
      end
      result
    end

    def append_predecessor(prev_state)
      @predecessors << prev_state
      @predecessors.uniq!
    end

    def goto_follow_set(nterm_token)
      return [] if nterm_token.accept_symbol?
      shift, next_state = @lalr_isocore.nterm_transitions.find {|sh, _| sh.next_sym == nterm_token }

      @kernels
        .select {|kernel| follow_kernel_items(shift, next_state, kernel) }
        .map {|kernel| item_lookahead_set[kernel] }
        .reduce(always_follows(shift, next_state)) {|result, terms| result |= terms }
    end

    def goto_follows(shift, next_state)
      queue = internal_dependencies(shift, next_state) + predecessor_dependencies(shift, next_state)
      terms = always_follows(shift, next_state)
      until queue.empty?
        st, sh, next_st = queue.pop
        terms |= st.always_follows(sh, next_st)
        st.internal_dependencies(sh, next_st).each {|v| queue << v }
        st.predecessor_dependencies(sh, next_st).each {|v| queue << v }
      end
      terms
    end

    def always_follows(shift, next_state)
      return @always_follows[[shift, next_state]] if @always_follows[[shift, next_state]]

      queue = internal_dependencies(shift, next_state) + successor_dependencies(shift, next_state)
      terms = []
      until queue.empty?
        st, sh, next_st = queue.pop
        terms |= next_st.term_transitions.map {|sh, _| sh.next_sym }
        st.internal_dependencies(sh, next_st).each {|v| queue << v }
        st.successor_dependencies(sh, next_st).each {|v| queue << v }
      end
      @always_follows[[shift, next_state]] = terms
    end

    def internal_dependencies(shift, next_state)
      return @internal_dependencies[[shift, next_state]] if @internal_dependencies[[shift, next_state]]

      syms = @items.select {|i|
        i.next_sym == shift.next_sym && i.symbols_after_transition.all?(&:nullable) && i.position == 0
      }.map(&:lhs).uniq
      @internal_dependencies[[shift, next_state]] = nterm_transitions.select {|sh, _| syms.include?(sh.next_sym) }.map {|goto| [self, *goto] }
    end

    def successor_dependencies(shift, next_state)
      return @successor_dependencies[[shift, next_state]] if @successor_dependencies[[shift, next_state]]

      @successor_dependencies[[shift, next_state]] =
        next_state.nterm_transitions
        .select {|next_shift, _| next_shift.next_sym.nullable }
        .map {|transition| [next_state, *transition] }
    end

    def predecessor_dependencies(shift, next_state)
      state_items = []
      @kernels.select {|kernel|
        kernel.next_sym == shift.next_sym && kernel.symbols_after_transition.all?(&:nullable)
      }.each do |item|
        queue = predecessors_with_item(item)
        until queue.empty?
          st, i = queue.pop
          if i.position == 0
            state_items << [st, i]
          else
            st.predecessors_with_item(i).each {|v| queue << v }
          end
        end
      end

      state_items.map {|state, item|
        sh, next_st = state.nterm_transitions.find {|shi, _| shi.next_sym == item.lhs }
        [state, sh, next_st]
      }
    end
  end
end
