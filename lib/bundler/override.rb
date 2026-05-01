# frozen_string_literal: true

module Bundler
  class Override
    LOWER_BOUND_OPERATORS = [">=", ">", "="].freeze

    attr_reader :target, :field, :operation

    def initialize(target, field, operation)
      @target = target
      @field = field
      @operation = operation
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

      lower_bounds = requirement.requirements.filter_map do |op, version|
        if LOWER_BOUND_OPERATORS.include?(op)
          [op, version]
        elsif op == "~>"
          [">=", version]
        end
      end

      return Gem::Requirement.default if lower_bounds.empty?

      Gem::Requirement.new(lower_bounds.map {|op, v| "#{op} #{v}" })
    end
  end
end
