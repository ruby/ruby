# frozen_string_literal: true

module Lrama
  class GrammarValidator
    def initialize(grammar, states, logger)
      @grammar = grammar
      @states = states
      @logger = logger
    end

    def valid?
      conflicts_within_threshold?
    end

    private

    def conflicts_within_threshold?
      return true unless @grammar.expect

      [sr_conflicts_within_threshold(@grammar.expect), rr_conflicts_within_threshold(0)].all?
    end

    def sr_conflicts_within_threshold(expected)
      return true if expected == @states.sr_conflicts_count

      @logger.error("shift/reduce conflicts: #{@states.sr_conflicts_count} found, #{expected} expected")
      false
    end

    def rr_conflicts_within_threshold(expected)
      return true if expected == @states.rr_conflicts_count

      @logger.error("reduce/reduce conflicts: #{@states.rr_conflicts_count} found, #{expected} expected")
      false
    end
  end
end
