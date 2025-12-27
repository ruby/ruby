# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class State
    # * state: A state on which the conflct is resolved
    # * symbol: A symbol under discussion
    # * reduce: A reduce under discussion
    # * which: For which a conflict is resolved. :shift, :reduce or :error (for nonassociative)
    # * resolved_by_precedence: If the conflict is resolved by precedence definition or not
    class ResolvedConflict
      # @rbs!
      #   type which_enum = :reduce | :shift | :error

      attr_reader :state #: State
      attr_reader :symbol #: Grammar::Symbol
      attr_reader :reduce #: State::Action::Reduce
      attr_reader :which #: which_enum
      attr_reader :resolved_by_precedence #: bool

      # @rbs (state: State, symbol: Grammar::Symbol, reduce: State::Action::Reduce, which: which_enum, resolved_by_precedence: bool) -> void
      def initialize(state:, symbol:, reduce:, which:, resolved_by_precedence:)
        @state = state
        @symbol = symbol
        @reduce = reduce
        @which = which
        @resolved_by_precedence = resolved_by_precedence
      end

      # @rbs () -> (::String | bot)
      def report_message
        "Conflict between rule #{reduce.rule.id} and token #{symbol.display_name} #{how_resolved}."
      end

      # @rbs () -> (::String | bot)
      def report_precedences_message
        "Conflict between reduce by \"#{reduce.rule.display_name}\" and shift #{symbol.display_name} #{how_resolved}."
      end

      private

      # @rbs () -> (::String | bot)
      def how_resolved
        s = symbol.display_name
        r = reduce.rule.precedence_sym&.display_name
        case
        when which == :shift && resolved_by_precedence
          msg = "resolved as #{which} (%right #{s})"
        when which == :shift
          msg = "resolved as #{which} (#{r} < #{s})"
        when which == :reduce && resolved_by_precedence
          msg = "resolved as #{which} (%left #{s})"
        when which == :reduce
          msg = "resolved as #{which} (#{s} < #{r})"
        when which == :error
          msg = "resolved as an #{which} (%nonassoc #{s})"
        else
          raise "Unknown direction. #{self}"
        end

        msg
      end
    end
  end
end
