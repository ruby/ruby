require 'json'

module Lrama
  class JsonReporter
    include Lrama::Report::Duration

    def initialize(states)
      @states = states
    end

    def report(io, **options)
      report_duration(:report) do
        _report(io, **options)
      end
    end

    private

    def _report(io, grammar: false, states: false, itemsets: false, lookaheads: false, solved: false, verbose: false)
      # TODO: Unused terms
      # TODO: Unused rules

      report_conflicts(io)
      report_grammar(io) if grammar
      report_states(io, itemsets, lookaheads, solved, verbose)
    end
  end
end
