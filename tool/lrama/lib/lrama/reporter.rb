# rbs_inline: enabled
# frozen_string_literal: true

require_relative 'reporter/conflicts'
require_relative 'reporter/grammar'
require_relative 'reporter/precedences'
require_relative 'reporter/profile'
require_relative 'reporter/rules'
require_relative 'reporter/states'
require_relative 'reporter/terms'

module Lrama
  class Reporter
    include Lrama::Tracer::Duration

    # @rbs (**bool options) -> void
    def initialize(**options)
      @options = options
      @rules = Rules.new(**options)
      @terms = Terms.new(**options)
      @conflicts = Conflicts.new
      @precedences = Precedences.new
      @grammar = Grammar.new(**options)
      @states = States.new(**options)
    end

    # @rbs (File io, Lrama::States states) -> void
    def report(io, states)
      report_duration(:report) do
        report_duration(:report_rules) { @rules.report(io, states) }
        report_duration(:report_terms) { @terms.report(io, states) }
        report_duration(:report_conflicts) { @conflicts.report(io, states) }
        report_duration(:report_precedences) { @precedences.report(io, states) }
        report_duration(:report_grammar) { @grammar.report(io, states) }
        report_duration(:report_states) { @states.report(io, states, ielr: states.ielr_defined?) }
      end
    end
  end
end
