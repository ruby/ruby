# frozen_string_literal: true

require_relative "vendored_tsort"

module Bundler
  class SpecSet
    include Enumerable
    include TSort

    def initialize(specs)
      @specs = specs
    end

    def for(dependencies, platforms_or_legacy_check = [nil], legacy_platforms = [nil], skips: [])
      platforms = if [true, false].include?(platforms_or_legacy_check)
        Bundler::SharedHelpers.major_deprecation 2,
          "SpecSet#for received a `check` parameter, but that's no longer used and deprecated. " \
          "SpecSet#for always implicitly performs validation. Please remove this parameter",
          print_caller_location: true

        legacy_platforms
      else
        platforms_or_legacy_check
      end

      materialize_dependencies(dependencies, platforms, skips: skips)

      @materializations.flat_map(&:specs).uniq
    end

    def normalize_platforms!(deps, platforms)
      remove_invalid_platforms!(deps, platforms)
      add_extra_platforms!(platforms)

      platforms.map! do |platform|
        next platform if platform == Gem::Platform::RUBY

        begin
          Integer(platform.version)
        rescue ArgumentError, TypeError
          next platform
        end

        less_specific_platform = Gem::Platform.new([platform.cpu, platform.os, nil])
        next platform if incomplete_for_platform?(deps, less_specific_platform)

        less_specific_platform
      end.uniq!
    end

    def add_originally_invalid_platforms!(platforms, originally_invalid_platforms)
      originally_invalid_platforms.each do |originally_invalid_platform|
        platforms << originally_invalid_platform if complete_platform(originally_invalid_platform)
      end
    end

    def remove_invalid_platforms!(deps, platforms, skips: [])
      invalid_platforms = []

      platforms.reject! do |platform|
        next false if skips.include?(platform)

        invalid = incomplete_for_platform?(deps, platform)
        invalid_platforms << platform if invalid
        invalid
      end

      invalid_platforms
    end

    def add_extra_platforms!(platforms)
      if @specs.empty?
        platforms.concat([Gem::Platform::RUBY]).uniq
        return
      end

      new_platforms = all_platforms.select do |platform|
        next if platforms.include?(platform)
        next unless Gem::Platform.generic(platform) == Gem::Platform::RUBY

        complete_platform(platform)
      end
      return if new_platforms.empty?

      platforms.concat(new_platforms)
      return if new_platforms.include?(Bundler.local_platform)

      less_specific_platform = new_platforms.find {|platform| platform != Gem::Platform::RUBY && Bundler.local_platform === platform && platform === Bundler.local_platform }
      platforms.delete(Bundler.local_platform) if less_specific_platform
    end

    def validate_deps(s)
      s.runtime_dependencies.each do |dep|
        next if dep.name == "bundler"

        return :missing unless names.include?(dep.name)
        return :invalid if none? {|spec| dep.matches_spec?(spec) }
      end

      :valid
    end

    def [](key)
      key = key.name if key.respond_to?(:name)
      lookup[key]&.reverse || []
    end

    def []=(key, value)
      delete_by_name(key)

      add_spec(value)
    end

    def delete(specs)
      Array(specs).each {|spec| remove_spec(spec) }
    end

    def sort!
      self
    end

    def to_a
      sorted.dup
    end

    def to_hash
      lookup.dup
    end

    def materialize(deps)
      materialize_dependencies(deps)

      SpecSet.new(materialized_specs)
    end

    # Materialize for all the specs in the spec set, regardless of what platform they're for
    # @return [Array<Gem::Specification>]
    def materialized_for_all_platforms
      @specs.map do |s|
        next s unless s.is_a?(LazySpecification)
        spec = s.materialize_for_cache
        raise GemNotFound, "Could not find #{s.full_name} in any of the sources" unless spec
        spec
      end
    end

    def incomplete_for_platform?(deps, platform)
      incomplete_specs_for_platform(deps, platform).any?
    end

    def incomplete_specs_for_platform(deps, platform)
      return [] if @specs.empty?

      validation_set = self.class.new(@specs)
      validation_set.for(deps, [platform])
      validation_set.incomplete_specs
    end

    def missing_specs_for(deps)
      materialize_dependencies(deps)

      missing_specs
    end

    def missing_specs
      @materializations.flat_map(&:completely_missing_specs)
    end

    def partially_missing_specs
      @materializations.flat_map(&:partially_missing_specs)
    end

    def incomplete_specs
      @materializations.flat_map(&:incomplete_specs)
    end

    def insecurely_materialized_specs
      materialized_specs.select(&:insecurely_materialized?)
    end

    def -(other)
      SharedHelpers.major_deprecation 2, "SpecSet#- has been removed with no replacement"

      SpecSet.new(to_a - other.to_a)
    end

    def find_by_name_and_platform(name, platform)
      @specs.detect {|spec| spec.name == name && spec.installable_on_platform?(platform) }
    end

    def specs_with_additional_variants_from(other)
      sorted | additional_variants_from(other)
    end

    def delete_by_name(name)
      @specs.reject! {|spec| spec.name == name }
      @sorted&.reject! {|spec| spec.name == name }
      return if @lookup.nil?

      @lookup[name] = nil
    end

    def version_for(name)
      exemplary_spec(name)&.version
    end

    def what_required(spec)
      unless req = find {|s| s.runtime_dependencies.any? {|d| d.name == spec.name } }
        return [spec]
      end
      what_required(req) << spec
    end

    def <<(spec)
      SharedHelpers.major_deprecation 2, "SpecSet#<< has been removed with no replacement"

      @specs << spec
    end

    def length
      @specs.length
    end

    def size
      @specs.size
    end

    def empty?
      @specs.empty?
    end

    def each(&b)
      sorted.each(&b)
    end

    def names
      lookup.keys
    end

    def valid?(s)
      s.matches_current_metadata? && valid_dependencies?(s)
    end

    def to_s
      map(&:full_name).to_s
    end

    private

    def materialize_dependencies(dependencies, platforms = [nil], skips: [])
      handled = ["bundler"].product(platforms).map {|k| [k, true] }.to_h
      deps = dependencies.product(platforms)
      @materializations = []

      loop do
        break unless dep = deps.shift

        dependency = dep[0]
        platform = dep[1]
        name = dependency.name

        key = [name, platform]
        next if handled.key?(key)

        handled[key] = true

        materialization = Materialization.new(dependency, platform, candidates: lookup[name])

        deps.concat(materialization.dependencies) if materialization.complete?

        @materializations << materialization unless skips.include?(name)
      end

      @materializations
    end

    def materialized_specs
      @materializations.filter_map(&:materialized_spec)
    end

    def complete_platform(platform)
      new_specs = []

      valid_platform = lookup.all? do |_, specs|
        spec = specs.first
        matching_specs = spec.source.specs.search([spec.name, spec.version])
        platform_spec = MatchPlatform.select_best_platform_match(matching_specs, platform).find do |s|
          valid?(s)
        end

        if platform_spec
          new_specs << LazySpecification.from_spec(platform_spec) unless specs.include?(platform_spec)
          true
        else
          false
        end
      end

      if valid_platform && new_specs.any?
        new_specs.each {|spec| add_spec(spec) }
      end

      valid_platform
    end

    def all_platforms
      @specs.flat_map {|spec| spec.source.specs.search([spec.name, spec.version]).map(&:platform) }.uniq
    end

    def additional_variants_from(other)
      other.select do |other_spec|
        spec = exemplary_spec(other_spec.name)
        next unless spec

        selected = spec.version == other_spec.version && valid_dependencies?(other_spec)
        other_spec.source = spec.source if selected
        selected
      end
    end

    def valid_dependencies?(s)
      validate_deps(s) == :valid
    end

    def sorted
      @sorted ||= ([@specs.find {|s| s.name == "rake" }] + tsort).compact.uniq
    rescue TSort::Cyclic => error
      cgems = extract_circular_gems(error)
      raise CyclicDependencyError, "Your bundle requires gems that depend" \
        " on each other, creating an infinite loop. Please remove either" \
        " gem '#{cgems[0]}' or gem '#{cgems[1]}' and try again."
    end

    def extract_circular_gems(error)
      error.message.scan(/@name="(.*?)"/).flatten
    end

    def lookup
      @lookup ||= begin
        lookup = {}
        @specs.each do |s|
          index_spec(lookup, s.name, s)
        end
        lookup
      end
    end

    def tsort_each_node
      # MUST sort by name for backwards compatibility
      @specs.sort_by(&:name).each {|s| yield s }
    end

    def tsort_each_child(s)
      s.dependencies.sort_by(&:name).each do |d|
        next if d.type == :development

        specs_for_name = lookup[d.name]
        next unless specs_for_name

        specs_for_name.each {|s2| yield s2 }
      end
    end

    def add_spec(spec)
      @specs << spec

      name = spec.name

      @sorted&.insert(@sorted.bsearch_index {|s| s.name >= name } || @sorted.size, spec)
      return if @lookup.nil?

      index_spec(@lookup, name, spec)
    end

    def remove_spec(spec)
      @specs.delete(spec)
      @sorted&.delete(spec)
      return if @lookup.nil?

      indexed_specs = @lookup[spec.name]
      return unless indexed_specs

      if indexed_specs.size > 1
        @lookup[spec.name].delete(spec)
      else
        @lookup[spec.name] = nil
      end
    end

    def index_spec(hash, key, value)
      hash[key] ||= []
      hash[key] << value
    end

    def exemplary_spec(name)
      self[name].first
    end
  end
end
