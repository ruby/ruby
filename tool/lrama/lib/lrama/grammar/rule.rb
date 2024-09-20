# frozen_string_literal: true

module Lrama
  class Grammar
    # _rhs holds original RHS element. Use rhs to refer to Symbol.
    class Rule < Struct.new(:id, :_lhs, :lhs, :lhs_tag, :_rhs, :rhs, :token_code, :position_in_original_rule_rhs, :nullable, :precedence_sym, :lineno, keyword_init: true)
      attr_accessor :original_rule

      def ==(other)
        self.class == other.class &&
        self.lhs == other.lhs &&
        self.lhs_tag == other.lhs_tag &&
        self.rhs == other.rhs &&
        self.token_code == other.token_code &&
        self.position_in_original_rule_rhs == other.position_in_original_rule_rhs &&
        self.nullable == other.nullable &&
        self.precedence_sym == other.precedence_sym &&
        self.lineno == other.lineno
      end

      def display_name
        l = lhs.id.s_value
        r = empty_rule? ? "ε" : rhs.map {|r| r.id.s_value }.join(" ")

        "#{l} -> #{r}"
      end

      # Used by #user_actions
      def as_comment
        l = lhs.id.s_value
        r = empty_rule? ? "%empty" : rhs.map(&:display_name).join(" ")

        "#{l}: #{r}"
      end

      def with_actions
        "#{display_name} {#{token_code&.s_value}}"
      end

      # opt_nl: ε     <-- empty_rule
      #       | '\n'  <-- not empty_rule
      def empty_rule?
        rhs.empty?
      end

      def precedence
        precedence_sym&.precedence
      end

      def initial_rule?
        id == 0
      end

      def translated_code
        return nil unless token_code

        Code::RuleAction.new(type: :rule_action, token_code: token_code, rule: self).translated_code
      end

      def contains_at_reference?
        return false unless token_code

        token_code.references.any? {|r| r.type == :at }
      end
    end
  end
end
