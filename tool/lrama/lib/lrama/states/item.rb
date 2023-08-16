# TODO: Validate position is not over rule rhs

module Lrama
  class States
    class Item < Struct.new(:rule, :position, keyword_init: true)
      # Optimization for States#setup_state
      def hash
        [rule.id, position].hash
      end

      def rule_id
        rule.id
      end

      def empty_rule?
        rule.empty_rule?
      end

      def number_of_rest_symbols
        rule.rhs.count - position
      end

      def lhs
        rule.lhs
      end

      def next_sym
        rule.rhs[position]
      end

      def next_next_sym
        rule.rhs[position + 1]
      end

      def previous_sym
        rule.rhs[position - 1]
      end

      def end_of_rule?
        rule.rhs.count == position
      end

      def beginning_of_rule?
        position == 0
      end

      def start_item?
        rule.id == 0 && position == 0
      end

      def new_by_next_position
        Item.new(rule: rule, position: position + 1)
      end

      def symbols_before_dot
        rule.rhs[0...position]
      end

      def symbols_after_dot
        rule.rhs[position..-1]
      end

      def to_s
        "#{lhs.id.s_value}: #{display_name}"
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
  end
end
