# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Tracer
    class Actions
      # @rbs (IO io, ?actions: bool, **bool options) -> void
      def initialize(io, actions: false, **options)
        @io = io
        @actions = actions
      end

      # @rbs (Lrama::Grammar grammar) -> void
      def trace(grammar)
        return unless @actions

        @io << "Grammar rules with actions:" << "\n"
        grammar.rules.each { |rule| @io << rule.with_actions << "\n" }
      end
    end
  end
end
