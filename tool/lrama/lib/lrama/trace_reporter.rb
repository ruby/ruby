# rbs_inline: enabled
# frozen_string_literal: true

module Lrama
  class TraceReporter
    # @rbs (Lrama::Grammar grammar) -> void
    def initialize(grammar)
      @grammar = grammar
    end

    # @rbs (**Hash[Symbol, bool] options) -> void
    def report(**options)
      _report(**options)
    end

    private

    # @rbs rules: (bool rules, bool actions, bool only_explicit_rules, **untyped _) -> void
    def _report(rules: false, actions: false, only_explicit_rules: false, **_)
      report_rules if rules && !only_explicit_rules
      report_only_explicit_rules if only_explicit_rules
      report_actions if actions
    end

    # @rbs () -> void
    def report_rules
      puts "Grammar rules:"
      @grammar.rules.each { |rule| puts rule.display_name }
    end

    # @rbs () -> void
    def report_only_explicit_rules
      puts "Grammar rules:"
      @grammar.rules.each do |rule|
        puts rule.display_name_without_action if rule.lhs.first_set.any?
      end
    end

    # @rbs () -> void
    def report_actions
      puts "Grammar rules with actions:"
      @grammar.rules.each { |rule| puts rule.with_actions }
    end
  end
end
