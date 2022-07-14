# frozen_string_literal: true

require_relative "vendored_tsort"

module Bundler
  class SpecSet
    include Enumerable
    include TSort

    def initialize(specs)
      @specs = specs
    end

    def for(dependencies, check = false, platforms = [nil])
      handled = ["bundler"].product(platforms).map {|k| [k, true] }.to_h
      deps = dependencies.product(platforms).map {|dep, platform| [dep.name, platform && dep.force_ruby_platform ? Gem::Platform::RUBY : platform] }
      specs = []

      loop do
        break unless dep = deps.shift
        next if handled.key?(dep)

        handled[dep] = true

        specs_for_dep = specs_for_dependency(*dep)
        if specs_for_dep.any?
          specs.concat(specs_for_dep)

          specs_for_dep.first.dependencies.each do |d|
            next if d.type == :development
            deps << [d.name, dep[1]]
          end
        elsif check
          specs << IncompleteSpecification.new(*dep)
        end
      end

      if spec = lookup["bundler"].first
        specs << spec
      end

      specs
    end

    def [](key)
      key = key.name if key.respond_to?(:name)
      lookup[key].reverse
    end

    def []=(key, value)
      @specs << value
      @lookup = nil
      @sorted = nil
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
      materialized = self.for(deps, true).uniq

      materialized.map! do |s|
        next s unless s.is_a?(LazySpecification)
        s.materialize_for_installation || s
      end
      SpecSet.new(materialized)
    end

    # Materialize for all the specs in the spec set, regardless of what platform they're for
    # This is in contrast to how for does platform filtering (and specifically different from how `materialize` calls `for` only for the current platform)
    # @return [Array<Gem::Specification>]
    def materialized_for_all_platforms
      @specs.map do |s|
        next s unless s.is_a?(LazySpecification)
        s.source.remote!
        spec = s.materialize_for_installation
        raise GemNotFound, "Could not find #{s.full_name} in any of the sources" unless spec
        spec
      end
    end

    def materialized_for_resolution
      materialized = @specs.map do |s|
        spec = s.materialize_for_resolution
        yield spec if spec
        spec
      end.compact
      SpecSet.new(materialized)
    end

    def missing_specs
      @specs.select {|s| s.is_a?(LazySpecification) }
    end

    def incomplete_specs
      @specs.select {|s| s.is_a?(IncompleteSpecification) }
    end

    def merge(set)
      arr = sorted.dup
      set.each do |set_spec|
        full_name = set_spec.full_name
        next if arr.any? {|spec| spec.full_name == full_name }
        arr << set_spec
      end
      SpecSet.new(arr)
    end

    def find_by_name_and_platform(name, platform)
      @specs.detect {|spec| spec.name == name && spec.match_platform(platform) }
    end

    def what_required(spec)
      unless req = find {|s| s.dependencies.any? {|d| d.type == :runtime && d.name == spec.name } }
        return [spec]
      end
      what_required(req) << spec
    end

    def <<(spec)
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

    private

    def sorted
      rake = @specs.find {|s| s.name == "rake" }
      begin
        @sorted ||= ([rake] + tsort).compact.uniq
      rescue TSort::Cyclic => error
        cgems = extract_circular_gems(error)
        raise CyclicDependencyError, "Your bundle requires gems that depend" \
          " on each other, creating an infinite loop. Please remove either" \
          " gem '#{cgems[1]}' or gem '#{cgems[0]}' and try again."
      end
    end

    def extract_circular_gems(error)
      error.message.scan(/@name="(.*?)"/).flatten
    end

    def lookup
      @lookup ||= begin
        lookup = Hash.new {|h, k| h[k] = [] }
        Index.sort_specs(@specs).reverse_each do |s|
          lookup[s.name] << s
        end
        lookup
      end
    end

    def tsort_each_node
      # MUST sort by name for backwards compatibility
      @specs.sort_by(&:name).each {|s| yield s }
    end

    def specs_for_dependency(name, platform)
      specs_for_name = lookup[name]
      if platform.nil?
        GemHelpers.select_best_platform_match(specs_for_name.select {|s| Gem::Platform.match_spec?(s) }, Bundler.local_platform)
      else
        specs_for_name_and_platform = GemHelpers.select_best_platform_match(specs_for_name, platform)
        specs_for_name_and_platform.any? ? specs_for_name_and_platform : specs_for_name
      end
    end

    def tsort_each_child(s)
      s.dependencies.sort_by(&:name).each do |d|
        next if d.type == :development
        lookup[d.name].each {|s2| yield s2 }
      end
    end
  end
end
