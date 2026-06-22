# rbs_inline: enabled
# frozen_string_literal: true

# TODO: Validate position is not over rule rhs

require "forwardable"

module Lrama
  class State
    class Item < Struct.new(:rule, :position, keyword_init: true)
      # @rbs!
      #   include Grammar::Rule::_DelegatedMethods
      #
      #   attr_accessor rule: Grammar::Rule
      #   attr_accessor position: Integer
      #
      #   def initialize: (?rule: Grammar::Rule, ?position: Integer) -> void

      extend Forwardable

      def_delegators "rule", :lhs, :rhs

      # Optimization for States#setup_state
      #
      # @rbs () -> Integer
      def hash
        [rule_id, position].hash
      end

      # @rbs () -> Integer
      def rule_id
        rule.id
      end

      # @rbs () -> bool
      def empty_rule?
        rule.empty_rule?
      end

      # @rbs () -> Integer
      def number_of_rest_symbols
        @number_of_rest_symbols ||= rhs.count - position
      end

      # @rbs () -> Grammar::Symbol
      def next_sym
        rhs[position]
      end

      # @rbs () -> Grammar::Symbol
      def next_next_sym
        @next_next_sym ||= rhs[position + 1]
      end

      # @rbs () -> Grammar::Symbol
      def previous_sym
        rhs[position - 1]
      end

      # @rbs () -> bool
      def end_of_rule?
        rhs.count == position
      end

      # @rbs () -> bool
      def beginning_of_rule?
        position == 0
      end

      # @rbs () -> bool
      def start_item?
        rule.initial_rule? && beginning_of_rule?
      end

      # @rbs () -> State::Item
      def new_by_next_position
        Item.new(rule: rule, position: position + 1)
      end

      # @rbs () -> Array[Grammar::Symbol]
      def symbols_before_dot # steep:ignore
        rhs[0...position]
      end

      # @rbs () -> Array[Grammar::Symbol]
      def symbols_after_dot # steep:ignore
        rhs[position..-1]
      end

      # @rbs () -> Array[Grammar::Symbol]
      def symbols_after_transition # steep:ignore
        rhs[position+1..-1]
      end

      # @rbs () -> ::String
      def to_s
        "#{lhs.id.s_value}: #{display_name}"
      end

      # @rbs () -> ::String
      def display_name
        r = rhs.map(&:display_name).insert(position, "•").join(" ")
        "#{r}  (rule #{rule_id})"
      end

      # Right after position
      #
      # @rbs () -> ::String
      def display_rest
        r = symbols_after_dot.map(&:display_name).join(" ")
        ". #{r}  (rule #{rule_id})"
      end

      # @rbs (State::Item other_item) -> bool
      def predecessor_item_of?(other_item)
        rule == other_item.rule && position == other_item.position - 1
      end
    end
  end
end
