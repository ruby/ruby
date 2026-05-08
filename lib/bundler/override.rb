# frozen_string_literal: true

module Bundler
  class Override
    UPPER_BOUND_OPERATORS = ["<", "<="].freeze

    def self.find_for(overrides, name, field)
      overrides.find {|o| o.target == name && o.field == field } ||
        overrides.find {|o| o.target == :all && o.field == field }
    end

    # Attach the given overrides onto every LazySpecification in `specs` so
    # downstream consumers (LazySpecification#choose_compatible, the install-
    # time compatibility check, etc.) can read the override list off the spec
    # itself. Non-LazySpec entries (StubSpecification, Gem::Specification, ...)
    # are left untouched.
    def self.attach(specs, overrides)
      return if overrides.nil? || overrides.empty?
      specs.each {|s| s.overrides = overrides if s.is_a?(LazySpecification) }
    end

    attr_reader :target, :field, :operation, :source_location

    def initialize(target, field, operation, source_location: nil)
      @target = target
      @field = field
      @operation = operation
      @source_location = source_location
    end

    def source_location_label
      return nil unless @source_location
      "#{File.basename(@source_location.path)}:#{@source_location.lineno}"
    end

    def apply_to(requirement)
      case operation
      when nil
        Gem::Requirement.default
      when :ignore_upper
        remove_upper_bounds(requirement)
      when String
        Gem::Requirement.new(operation)
      else
        raise ArgumentError, "unsupported override operation: #{operation.inspect}"
      end
    end

    private

    def remove_upper_bounds(requirement)
      return Gem::Requirement.default if requirement.nil? || requirement.none?

      preserved = requirement.requirements.filter_map do |op, version|
        if UPPER_BOUND_OPERATORS.include?(op)
          nil
        elsif op == "~>"
          [">=", version]
        else
          [op, version]
        end
      end

      return Gem::Requirement.default if preserved.empty?

      Gem::Requirement.new(preserved.map {|op, v| "#{op} #{v}" })
    end
  end
end
