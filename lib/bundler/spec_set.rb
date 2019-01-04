# frozen_string_literal: true

require "tsort"
require "set"

module Bundler
  class SpecSet
    include Enumerable
    include TSort

    def initialize(specs)
      @specs = specs
    end

    def for(dependencies, skip = [], check = false, match_current_platform = false, raise_on_missing = true)
      handled = Set.new
      deps = dependencies.dup
      specs = []
      skip += ["bundler"]

      loop do
        break unless dep = deps.shift
        next if !handled.add?(dep) || skip.include?(dep.name)

        if spec = spec_for_dependency(dep, match_current_platform)
          specs << spec

          spec.dependencies.each do |d|
            next if d.type == :development
            d = DepProxy.new(d, dep.__platform) unless match_current_platform
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

      check ? true : SpecSet.new(specs)
    end

    def valid_for?(deps)
      self.for(deps, [], true)
    end

    def [](key)
      key = key.name if key.respond_to?(:name)
      lookup[key].reverse
    end

    def []=(key, value)
      @specs << value
      @lookup = nil
      @sorted = nil
      value
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
      materialized = self.for(deps, [], false, true, !missing_specs).to_a
      deps = materialized.map(&:name).uniq
      materialized.map! do |s|
        next s unless s.is_a?(LazySpecification)
        s.source.dependency_names = deps if s.source.respond_to?(:dependency_names=)
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
      names = @specs.map(&:name).uniq
      @specs.map do |s|
        next s unless s.is_a?(LazySpecification)
        s.source.dependency_names = names if s.source.respond_to?(:dependency_names=)
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
      if Bundler.current_ruby.mri? && Bundler.current_ruby.on_19?
        error.message.scan(/(\w+) \([^)]/).flatten
      else
        error.message.scan(/@name="(.*?)"/).flatten
      end
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
        Bundler.rubygems.platforms.reverse_each do |pl|
          match = GemHelpers.select_best_platform_match(specs_for_platforms, pl)
          return match if match
        end
        nil
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
