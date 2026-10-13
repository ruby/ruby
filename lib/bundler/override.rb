# frozen_string_literal: true

module Bundler
  class Override
    UPPER_BOUND_OPERATORS = ["<", "<="].freeze

    def self.find_for(overrides, name, field)
      overrides.find {|o| o.target == name && o.field == field } ||
        overrides.find {|o| o.target == :all && o.field == field }
    end

    # Drops or replaces the dependencies of the gem named `from` that a
    # `from:`/`to:` override targets. The requirement `from` put on the
    # replaced gem is discarded.
    def self.rewrite_dependencies(overrides, from, dependencies)
      return dependencies if overrides.nil? || overrides.none? {|o| o.from == from }

      dependencies.filter_map do |dep|
        override = overrides.find {|o| o.from == from && o.target == dep.name }
        next dep unless override
        next unless override.operation
        Gem::Dependency.new(override.operation, *Array(override.requirement))
      end
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

    attr_reader :target, :field, :operation, :from, :requirement, :source_location

    def initialize(target, field, operation, from: nil, requirement: nil, source_location: nil)
      @target = target
      @field = field
      @operation = operation
      @from = from
      @requirement = requirement
      @source_location = source_location
    end

    def source_location_label
      return nil unless @source_location
      "#{File.basename(@source_location.path)}:#{@source_location.lineno}"
    end

    def to_s
      options = if @from
        ["from: #{@from.inspect}", "to: #{@operation.inspect}", *("version: #{@requirement.inspect}" if @requirement)].join(", ")
      else
        "#{@field}: #{@operation.inspect}"
      end
      location = source_location_label
      "override #{@target == :all ? ":all" : @target.inspect}, #{options}#{" (declared at #{location})" if location}"
    end

    def apply_to(requirement)
      raise ArgumentError, "#{self} rewrites a dependency and has no requirement to apply" if @from

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
