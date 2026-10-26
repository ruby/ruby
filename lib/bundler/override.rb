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
      location = source_location_label
      "override #{to_lock}#{" (declared at #{location})" if location}"
    end

    # The override as recorded in the OVERRIDES section of Gemfile.lock: the
    # `override` arguments with requirements normalized, so equivalent
    # spellings ("<=3", "<= 3") record the same line.
    def to_lock
      target = @target == :all ? ":all" : @target.inspect
      fields = if @from
        ["from: #{@from.inspect}", "to: #{@operation.inspect}", *("version: #{self.class.normalize(@requirement).inspect}" if @requirement)]
      else
        ["#{@field}: #{self.class.normalize(@operation).inspect}"]
      end
      [target, *fields].join(", ")
    end

    LOCK_VALUE = /"[^"\\]*"|:[a-z_]+|nil/
    LOCK_FIELD = /, ([a-z_]+): (#{LOCK_VALUE})/
    LOCK_LINE = /\A(:all|"[a-zA-Z0-9._-]+")((?:#{LOCK_FIELD})+)\z/
    private_constant :LOCK_VALUE, :LOCK_FIELD, :LOCK_LINE

    # Parses a line written by #to_lock. The DSL only accepts valid gem names,
    # and requirements are normalized, so no recorded value contains a quote
    # or a backslash and the line can be read without evaluating it.
    def self.from_lock(line)
      match = LOCK_LINE.match(line)
      raise ArgumentError, "invalid override in lockfile: #{line.inspect}" unless match

      target = match[1] == ":all" ? :all : match[1][1..-2]
      fields = match[2].scan(LOCK_FIELD).map {|key, value| [key.to_sym, parse_lock_value(value)] }
      keys = fields.map(&:first)
      raise ArgumentError, "invalid override in lockfile: #{line.inspect}" unless keys.uniq.size == keys.size
      fields = fields.to_h

      if fields.key?(:from)
        unless (keys - [:from, :to, :version]).empty? && fields.key?(:to) && fields[:from].is_a?(String)
          raise ArgumentError, "invalid override in lockfile: #{line.inspect}"
        end
        new(target, :to, fields[:to], from: fields[:from], requirement: normalize(fields[:version]))
      else
        field, operation = fields.first
        unless fields.size == 1 && Dsl::SUPPORTED_OVERRIDE_FIELDS.include?(field)
          raise ArgumentError, "invalid override in lockfile: #{line.inspect}"
        end
        new(target, field, normalize(operation))
      end
    end

    def self.parse_lock_value(value)
      case value
      when "nil" then nil
      when /\A:/ then value[1..].to_sym
      else value[1..-2]
      end
    end
    private_class_method :parse_lock_value

    def self.normalize(operation)
      operation.is_a?(String) ? Gem::Requirement.new(operation).to_s : operation
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
