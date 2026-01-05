# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Tracer
    class State
      # @rbs (IO io, ?automaton: bool, ?closure: bool, **bool) -> void
      def initialize(io, automaton: false, closure: false, **_)
        @io = io
        @state = automaton || closure
      end

      # @rbs (Lrama::State state) -> void
      def trace(state)
        return unless @state

        # Bison 3.8.2 renders "(reached by "end-of-input")" for State 0 but
        # I think it is not correct...
        previous = state.kernels.first.previous_sym
        @io << "Processing state #{state.id} (reached by #{previous.display_name})" << "\n"
      end

      # @rbs (Integer state_count, Lrama::State state) -> void
      def trace_list_append(state_count, state)
        return unless @state

        previous = state.kernels.first.previous_sym
        @io << sprintf("state_list_append (state = %d, symbol = %d (%s))",
                        state_count, previous.number, previous.display_name) << "\n"
      end
    end
  end
end
