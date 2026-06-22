# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Conflicts
      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        report_conflicts(io, states)
      end

      private

      # @rbs (IO io, Lrama::States states) -> void
      def report_conflicts(io, states)
        has_conflict = false

        states.states.each do |state|
          messages = format_conflict_messages(state.conflicts)

          unless messages.empty?
            has_conflict = true
            io << "State #{state.id} conflicts: #{messages.join(', ')}\n"
          end
        end

        io << "\n\n" if has_conflict
      end

      # @rbs (Array[(Lrama::State::ShiftReduceConflict | Lrama::State::ReduceReduceConflict)] conflicts) -> Array[String]
      def format_conflict_messages(conflicts)
        conflict_types = {
          shift_reduce: "shift/reduce",
          reduce_reduce: "reduce/reduce"
        }

        conflict_types.keys.map do |type|
          type_conflicts = conflicts.select { |c| c.type == type }
          "#{type_conflicts.count} #{conflict_types[type]}" unless type_conflicts.empty?
        end.compact
      end
    end
  end
end
