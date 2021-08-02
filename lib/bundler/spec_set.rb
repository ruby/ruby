# frozen_string_literal: true

require "tsort"

module Bundler
  class SpecSet
    include Enumerable
    include TSort

    def initialize(specs)
      @specs = specs
    end

    def for(dependencies, skip = [], check = false, match_current_platform = false, raise_on_missing = true)
      handled = []
      deps = dependencies.dup
      specs = []
      skip += ["bundler"]

      loop do
        break unless dep = deps.shift
        next if handled.include?(dep) || skip.include?(dep.name)

        handled << dep

        specs_for_dep = spec_for_dependency(dep, match_current_platform)
        if specs_for_dep.any?
          specs += specs_for_dep

          specs_for_dep.first.dependencies.each do |d|
            next if d.type == :development
            d = DepProxy.get_proxy(d, dep.__platform) unless match_current_platform
            deps << d
          end
        elsif check
          return false
        elsif raise_on_missing
          others = lookup[dep.name] if match_current_platform
          message = "Unable to find a spec satisfying #{dep} in the set. Perhaps the lockfile is corrupted?"
          message += " Found #{others.join(", ")} that did not match the current platform." if others && !others.empty?
          raise GemNotFound, message
        end
      end

      if spec = lookup["bundler"].first
        specs << spec
      end

      check ? true : specs
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

    def materialize(deps, missing_specs = nil)
      materialized = self.for(deps, [], false, true, !missing_specs)

      materialized.group_by(&:source).each do |source, specs|
        next unless specs.any?{|s| s.is_a?(LazySpecification) }

        source.local!
        names = -> { specs.map(&:name).uniq }
        source.double_check_for(names)
      end

      materialized.map! do |s|
        next s unless s.is_a?(LazySpecification)
        spec = s.__materialize__
        unless spec
          unless missing_specs
            raise GemNotFound, "Could not find #{s.full_name} in any of the sources"
          end
          missing_specs << s
        end
        spec
      end
      SpecSet.new(missing_specs ? materialized.compact : materialized)
    end

    # Materialize for all the specs in the spec set, regardless of what platform they're for
    # This is in contrast to how for does platform filtering (and specifically different from how `materialize` calls `for` only for the current platform)
    # @return [Array<Gem::Specification>]
    def materialized_for_all_platforms
      @specs.group_by(&:source).each do |source, specs|
        next unless specs.any?{|s| s.is_a?(LazySpecification) }

        source.local!
        source.remote!
        names = -> { specs.map(&:name).uniq }
        source.double_check_for(names)
      end

      @specs.map do |s|
        next s unless s.is_a?(LazySpecification)
        spec = s.__materialize__
        raise GemNotFound, "Could not find #{s.full_name} in any of the sources" unless spec
        spec
      end
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

    def spec_for_dependency(dep, match_current_platform)
      specs_for_platforms = lookup[dep.name]
      if match_current_platform
        GemHelpers.select_best_platform_match(specs_for_platforms.select{|s| Gem::Platform.match_spec?(s) }, Bundler.local_platform)
      else
        GemHelpers.select_best_platform_match(specs_for_platforms, dep.__platform)
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
