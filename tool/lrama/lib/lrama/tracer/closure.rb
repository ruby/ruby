# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Tracer
    class Closure
      # @rbs (IO io, ?automaton: bool, ?closure: bool, **bool) -> void
      def initialize(io, automaton: false, closure: false, **_)
        @io = io
        @closure = automaton || closure
      end

      # @rbs (Lrama::State state) -> void
      def trace(state)
        return unless @closure

        @io << "Closure: input" << "\n"
        state.kernels.each do |item|
          @io << "  #{item.display_rest}" << "\n"
        end
        @io << "\n\n"
        @io << "Closure: output" << "\n"
        state.items.each do |item|
          @io << "  #{item.display_rest}" << "\n"
        end
        @io << "\n\n"
      end
    end
  end
end
