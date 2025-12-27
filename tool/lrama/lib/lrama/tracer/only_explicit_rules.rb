# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Tracer
    class OnlyExplicitRules
      # @rbs (IO io, ?only_explicit: bool, **bool) -> void
      def initialize(io, only_explicit: false, **_)
        @io = io
        @only_explicit = only_explicit
      end

      # @rbs (Lrama::Grammar grammar) -> void
      def trace(grammar)
        return unless @only_explicit

        @io << "Grammar rules:" << "\n"
        grammar.rules.each do |rule|
          @io << rule.display_name_without_action << "\n" if rule.lhs.first_set.any?
        end
      end
    end
  end
end
