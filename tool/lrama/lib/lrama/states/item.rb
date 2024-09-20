# frozen_string_literal: true

# TODO: Validate position is not over rule rhs

require "forwardable"

module Lrama
  class States
    class Item < Struct.new(:rule, :position, keyword_init: true)
      extend Forwardable

      def_delegators "rule", :lhs, :rhs

      # Optimization for States#setup_state
      def hash
        [rule_id, position].hash
      end

      def rule_id
        rule.id
      end

      def empty_rule?
        rule.empty_rule?
      end

      def number_of_rest_symbols
        rhs.count - position
      end

      def next_sym
        rhs[position]
      end

      def next_next_sym
        rhs[position + 1]
      end

      def previous_sym
        rhs[position - 1]
      end

      def end_of_rule?
        rhs.count == position
      end

      def beginning_of_rule?
        position == 0
      end

      def start_item?
        rule.initial_rule? && beginning_of_rule?
      end

      def new_by_next_position
        Item.new(rule: rule, position: position + 1)
      end

      def symbols_before_dot # steep:ignore
        rhs[0...position]
      end

      def symbols_after_dot # steep:ignore
        rhs[position..-1]
      end

      def to_s
        "#{lhs.id.s_value}: #{display_name}"
      end

      def display_name
        r = rhs.map(&:display_name).insert(position, "•").join(" ")
        "#{r}  (rule #{rule_id})"
      end

      # Right after position
      def display_rest
        r = symbols_after_dot.map(&:display_name).join(" ")
        ". #{r}  (rule #{rule_id})"
      end
    end
  end
end
