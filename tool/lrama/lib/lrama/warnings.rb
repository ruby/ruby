# rbs_inline: enabled
# frozen_string_literal: true

require_relative 'warnings/conflicts'
require_relative 'warnings/implicit_empty'
require_relative 'warnings/name_conflicts'
require_relative 'warnings/redefined_rules'
require_relative 'warnings/required'
require_relative 'warnings/useless_precedence'

module Lrama
  class Warnings
    # @rbs (Logger logger, bool warnings) -> void
    def initialize(logger, warnings)
      @conflicts = Conflicts.new(logger, warnings)
      @implicit_empty = ImplicitEmpty.new(logger, warnings)
      @name_conflicts = NameConflicts.new(logger, warnings)
      @redefined_rules = RedefinedRules.new(logger, warnings)
      @required = Required.new(logger, warnings)
      @useless_precedence = UselessPrecedence.new(logger, warnings)
    end

    # @rbs (Lrama::Grammar grammar, Lrama::States states) -> void
    def warn(grammar, states)
      @conflicts.warn(states)
      @implicit_empty.warn(grammar)
      @name_conflicts.warn(grammar)
      @redefined_rules.warn(grammar)
      @required.warn(grammar)
      @useless_precedence.warn(grammar, states)
    end
  end
end
