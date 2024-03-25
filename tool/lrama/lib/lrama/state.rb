require "lrama/state/reduce"
require "lrama/state/reduce_reduce_conflict"
require "lrama/state/resolved_conflict"
require "lrama/state/shift"
require "lrama/state/shift_reduce_conflict"

module Lrama
  class State
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

    # Returns array of [Shift, next_state]
    def nterm_transitions
      return @nterm_transitions if @nterm_transitions

      @nterm_transitions = []

      shifts.each do |shift|
        next if shift.next_sym.term?

        @nterm_transitions << [shift, @items_to_state[shift.next_items]]
      end

      @nterm_transitions
    end

    # Returns array of [Shift, next_state]
    def term_transitions
      return @term_transitions if @term_transitions

      @term_transitions = []

      shifts.each do |shift|
        next if shift.next_sym.nterm?

        @term_transitions << [shift, @items_to_state[shift.next_items]]
      end

      @term_transitions
    end

    def transitions
      term_transitions + nterm_transitions
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
  end
end
