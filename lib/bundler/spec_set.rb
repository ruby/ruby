# frozen_string_literal: true
require "tsort"
require "forwardable"

module Bundler
  class SpecSet
    extend Forwardable
    include TSort, Enumerable

    def_delegators :@specs, :<<, :length, :add, :remove, :size, :empty?
    def_delegators :sorted, :each

    def initialize(specs)
      @specs = specs.sort_by(&:name)
    end

    def for(dependencies, skip = [], check = false, match_current_platform = false)
      handled = {}
      deps = dependencies.dup
      specs = []
      skip += ["bundler"]

      until deps.empty?
        dep = deps.shift
        next if handled[dep] || skip.include?(dep.name)

        handled[dep] = true

        if spec = spec_for_dependency(dep, match_current_platform)
          specs << spec

          spec.dependencies.each do |d|
            next if d.type == :development
            d = DepProxy.new(d, dep.__platform) unless match_current_platform
            deps << d
          end
        elsif check
          return false
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
      materialized = self.for(deps, [], false, true).to_a
      deps = materialized.map(&:name).uniq
      materialized.map! do |s|
        next s unless s.is_a?(LazySpecification)
        s.source.dependency_names = deps if s.source.respond_to?(:dependency_names=)
        spec = s.__materialize__
        if missing_specs
          missing_specs << s unless spec
        else
          raise GemNotFound, "Could not find #{s.full_name} in any of the sources" unless spec
        end
        spec if spec
      end
      SpecSet.new(materialized.compact)
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
      set.each do |s|
        next if arr.any? {|s2| s2.name == s.name && s2.version == s.version && s2.platform == s.platform }
        arr << s
      end
      SpecSet.new(arr)
    end

    def find_by_name_and_platform(name, platform)
      @specs.detect {|spec| spec.name == name && spec.match_platform(platform) }
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
      @specs.each {|s| yield s }
    end

    def spec_for_dependency(dep, match_current_platform)
      if match_current_platform
        Bundler.rubygems.platforms.reverse_each do |pl|
          match = GemHelpers.select_best_platform_match(lookup[dep.name], pl)
          return match if match
        end
        nil
      else
        GemHelpers.select_best_platform_match(lookup[dep.name], dep.__platform)
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
