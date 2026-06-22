# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class Reporter
    class Terms
      # @rbs (?terms: bool, **bool _) -> void
      def initialize(terms: false, **_)
        @terms = terms
      end

      # @rbs (IO io, Lrama::States states) -> void
      def report(io, states)
        return unless @terms

        look_aheads = states.states.each do |state|
          state.reduces.flat_map do |reduce|
            reduce.look_ahead unless reduce.look_ahead.nil?
          end
        end

        next_terms = states.states.flat_map do |state|
          state.term_transitions.map {|shift| shift.next_sym }
        end

        unused_symbols = states.terms.reject do |term|
          (look_aheads + next_terms).include?(term)
        end

        io << states.terms.count << " Terms\n\n"

        io << states.nterms.count << " Non-Terminals\n\n"

        unless unused_symbols.empty?
          io << "#{unused_symbols.count} Unused Terms\n\n"
          unused_symbols.each_with_index do |term, index|
            io << sprintf("%5d %s", index, term.id.s_value) << "\n"
          end
          io << "\n\n"
        end
      end
    end
  end
end
