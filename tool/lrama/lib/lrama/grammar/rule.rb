# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    # _rhs holds original RHS element. Use rhs to refer to Symbol.
    class Rule < Struct.new(:id, :_lhs, :lhs, :lhs_tag, :_rhs, :rhs, :token_code, :position_in_original_rule_rhs, :nullable, :precedence_sym, :lineno, keyword_init: true)
      # @rbs!
      #
      #   interface _DelegatedMethods
      #     def lhs: -> Grammar::Symbol
      #     def rhs: -> Array[Grammar::Symbol]
      #   end
      #
      #   attr_accessor id: Integer
      #   attr_accessor _lhs: Lexer::Token::Base
      #   attr_accessor lhs: Grammar::Symbol
      #   attr_accessor lhs_tag: Lexer::Token::Tag?
      #   attr_accessor _rhs: Array[Lexer::Token::Base]
      #   attr_accessor rhs: Array[Grammar::Symbol]
      #   attr_accessor token_code: Lexer::Token::UserCode?
      #   attr_accessor position_in_original_rule_rhs: Integer
      #   attr_accessor nullable: bool
      #   attr_accessor precedence_sym: Grammar::Symbol?
      #   attr_accessor lineno: Integer?
      #
      #   def initialize: (
      #     ?id: Integer, ?_lhs: Lexer::Token::Base?, ?lhs: Lexer::Token::Base, ?lhs_tag: Lexer::Token::Tag?, ?_rhs: Array[Lexer::Token::Base], ?rhs: Array[Grammar::Symbol],
      #     ?token_code: Lexer::Token::UserCode?, ?position_in_original_rule_rhs: Integer?, ?nullable: bool,
      #     ?precedence_sym: Grammar::Symbol?, ?lineno: Integer?
      #   ) -> void

      attr_accessor :original_rule #: Rule

      # @rbs (Rule other) -> bool
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

      # @rbs () -> String
      def display_name
        l = lhs.id.s_value
        r = empty_rule? ? "ε" : rhs.map {|r| r.id.s_value }.join(" ")
        "#{l} -> #{r}"
      end

      # @rbs () -> String
      def display_name_without_action
        l = lhs.id.s_value
        r = empty_rule? ? "ε" : rhs.map do |r|
          r.id.s_value if r.first_set.any?
        end.compact.join(" ")

        "#{l} -> #{r}"
      end

      # @rbs () -> (RailroadDiagrams::Skip | RailroadDiagrams::Sequence)
      def to_diagrams
        if rhs.empty?
          RailroadDiagrams::Skip.new
        else
          RailroadDiagrams::Sequence.new(*rhs_to_diagram)
        end
      end

      # Used by #user_actions
      #
      # @rbs () -> String
      def as_comment
        l = lhs.id.s_value
        r = empty_rule? ? "%empty" : rhs.map(&:display_name).join(" ")

        "#{l}: #{r}"
      end

      # @rbs () -> String
      def with_actions
        "#{display_name} {#{token_code&.s_value}}"
      end

      # opt_nl: ε     <-- empty_rule
      #       | '\n'  <-- not empty_rule
      #
      # @rbs () -> bool
      def empty_rule?
        rhs.empty?
      end

      # @rbs () -> Precedence?
      def precedence
        precedence_sym&.precedence
      end

      # @rbs () -> bool
      def initial_rule?
        id == 0
      end

      # @rbs () -> String?
      def translated_code
        return nil unless token_code

        Code::RuleAction.new(type: :rule_action, token_code: token_code, rule: self).translated_code
      end

      # @rbs () -> bool
      def contains_at_reference?
        return false unless token_code

        token_code.references.any? {|r| r.type == :at }
      end

      private

      # @rbs () -> Array[(RailroadDiagrams::Terminal | RailroadDiagrams::NonTerminal)]
      def rhs_to_diagram
        rhs.map do |r|
          if r.term
            RailroadDiagrams::Terminal.new(r.id.s_value)
          else
            RailroadDiagrams::NonTerminal.new(r.id.s_value)
          end
        end
      end
    end
  end
end
