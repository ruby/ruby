# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Precedences
      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        report_precedences(io, states)
      end

      private

      # @rbs (IO io, Lrama::States states) -> void
      def report_precedences(io, states)
        used_precedences = states.precedences.select(&:used_by?)

        return if used_precedences.empty?

        io << "Precedences\n\n"

        used_precedences.each do |precedence|
          io << "  precedence on #{precedence.symbol.display_name} is used to resolve conflict on\n"

          if precedence.used_by_lalr?
            io << "    LALR\n"

            precedence.used_by_lalr.uniq.sort_by do |resolved_conflict|
              resolved_conflict.state.id
            end.each do |resolved_conflict|
              io << "      state #{resolved_conflict.state.id}. #{resolved_conflict.report_precedences_message}\n"
            end

            io << "\n"
          end

          if precedence.used_by_ielr?
            io << "    IELR\n"

            precedence.used_by_ielr.uniq.sort_by do |resolved_conflict|
              resolved_conflict.state.id
            end.each do |resolved_conflict|
              io << "      state #{resolved_conflict.state.id}. #{resolved_conflict.report_precedences_message}\n"
            end

            io << "\n"
          end
        end

        io << "\n"
      end
    end
  end
end
