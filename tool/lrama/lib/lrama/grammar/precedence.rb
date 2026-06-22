# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Grammar
    class Precedence < Struct.new(:type, :symbol, :precedence, :s_value, :lineno, keyword_init: true)
      include Comparable
      # @rbs!
      #   type type_enum = :left | :right | :nonassoc | :precedence
      #
      #   attr_accessor type: type_enum
      #   attr_accessor symbol: Grammar::Symbol
      #   attr_accessor precedence: Integer
      #   attr_accessor s_value: String
      #   attr_accessor lineno: Integer
      #
      #   def initialize: (?type: type_enum, ?symbol: Grammar::Symbol, ?precedence: Integer, ?s_value: ::String, ?lineno: Integer) -> void

      attr_reader :used_by_lalr #: Array[State::ResolvedConflict]
      attr_reader :used_by_ielr #: Array[State::ResolvedConflict]

      # @rbs (Precedence other) -> Integer
      def <=>(other)
        self.precedence <=> other.precedence
      end

      # @rbs (State::ResolvedConflict resolved_conflict) -> void
      def mark_used_by_lalr(resolved_conflict)
        @used_by_lalr ||= [] #: Array[State::ResolvedConflict]
        @used_by_lalr << resolved_conflict
      end

      # @rbs (State::ResolvedConflict resolved_conflict) -> void
      def mark_used_by_ielr(resolved_conflict)
        @used_by_ielr ||= [] #: Array[State::ResolvedConflict]
        @used_by_ielr << resolved_conflict
      end

      # @rbs () -> bool
      def used_by?
        used_by_lalr? || used_by_ielr?
      end

      # @rbs () -> bool
      def used_by_lalr?
        !@used_by_lalr.nil? && !@used_by_lalr.empty?
      end

      # @rbs () -> bool
      def used_by_ielr?
        !@used_by_ielr.nil? && !@used_by_ielr.empty?
      end
    end
  end
end
