# rbs_inline: enabled
# frozen_string_literal: true

require_relative "tracer/actions"
require_relative "tracer/closure"
require_relative "tracer/duration"
require_relative "tracer/only_explicit_rules"
require_relative "tracer/rules"
require_relative "tracer/state"

module Lrama
  class Tracer
    # @rbs (IO io, **bool options) -> void
    def initialize(io, **options)
      @io = io
      @options = options
      @only_explicit_rules = OnlyExplicitRules.new(io, **options)
      @rules = Rules.new(io, **options)
      @actions = Actions.new(io, **options)
      @closure = Closure.new(io, **options)
      @state = State.new(io, **options)
    end

    # @rbs (Lrama::Grammar grammar) -> void
    def trace(grammar)
      @only_explicit_rules.trace(grammar)
      @rules.trace(grammar)
      @actions.trace(grammar)
    end

    # @rbs (Lrama::State state) -> void
    def trace_closure(state)
      @closure.trace(state)
    end

    # @rbs (Lrama::State state) -> void
    def trace_state(state)
      @state.trace(state)
    end

    # @rbs (Integer state_count, Lrama::State state) -> void
    def trace_state_list_append(state_count, state)
      @state.trace_list_append(state_count, state)
    end

    # @rbs () -> void
    def enable_duration
      Duration.enable if @options[:time]
    end
  end
end
