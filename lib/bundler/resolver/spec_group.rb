# frozen_string_literal: true

module Bundler
  class Resolver
    class SpecGroup
      def initialize(specs)
        @specs = specs
      end

      def empty?
        @specs.empty?
      end

      def name
        @name ||= exemplary_spec.name
      end

      def version
        @version ||= exemplary_spec.version
      end

      def source
        @source ||= exemplary_spec.source
      end

      def to_specs(force_ruby_platform)
        @specs.map do |s|
          lazy_spec = LazySpecification.from_spec(s)
          lazy_spec.force_ruby_platform = force_ruby_platform
          lazy_spec
        end
      end

      def to_s
        sorted_spec_names.join(", ")
      end

      def dependencies
        @dependencies ||= @specs.map do |spec|
          __dependencies(spec) + metadata_dependencies(spec)
        end.flatten.uniq
      end

      protected

      def sorted_spec_names
        @sorted_spec_names ||= @specs.map(&:full_name).sort
      end

      private

      def exemplary_spec
        @specs.first
      end

      def __dependencies(spec)
        dependencies = []
        spec.dependencies.each do |dep|
          next if dep.type == :development
          dependencies << Dependency.new(dep.name, dep.requirement)
        end
        dependencies
      end

      def metadata_dependencies(spec)
        [
          metadata_dependency("Ruby", spec.required_ruby_version),
          metadata_dependency("RubyGems", spec.required_rubygems_version),
        ].compact
      end

      def metadata_dependency(name, requirement)
        return if requirement.nil? || requirement.none?

        Dependency.new("#{name}\0", requirement)
      end
    end
  end
end
