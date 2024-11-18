# frozen_string_literal: true

module Bundler
  #
  # This class materializes a set of resolved specifications (`LazySpecification`)
  # for a given gem into the most appropriate real specifications
  # (`StubSepecification`, `EndpointSpecification`, etc), given a dependency and a
  # target platform.
  #
  class Materialization
    def initialize(dep, platform, candidates:)
      @dep = dep
      @platform = platform
      @candidates = candidates
    end

    def complete?
      specs.any?
    end

    def specs
      @specs ||= if @candidates.nil?
        []
      elsif platform
        GemHelpers.select_best_platform_match(@candidates, platform, force_ruby: dep.force_ruby_platform)
      else
        GemHelpers.select_best_local_platform_match(@candidates, force_ruby: dep.force_ruby_platform || dep.default_force_ruby_platform)
      end
    end

    def dependencies
      specs.first.runtime_dependencies.map {|d| [d, platform] }
    end

    def materialized_spec
      specs.reject(&:missing?).first&.materialization
    end

    def completely_missing_specs
      return [] unless specs.all?(&:missing?)

      specs
    end

    def partially_missing_specs
      specs.select(&:missing?)
    end

    def incomplete_specs
      return [] if complete?

      @candidates || LazySpecification.new(dep.name, nil, nil)
    end

    private

    attr_reader :dep, :platform
  end
end
