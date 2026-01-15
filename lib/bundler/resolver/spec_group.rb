# frozen_string_literal: true

module Bundler
  class Resolver
    class SpecGroup
      attr_reader :specs

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

      def to_specs(force_ruby_platform, most_specific_locked_platform)
        @specs.map do |s|
          lazy_spec = LazySpecification.from_spec(s)
          lazy_spec.force_ruby_platform = force_ruby_platform
          lazy_spec.most_specific_locked_platform = most_specific_locked_platform
          lazy_spec
        end
      end

      def to_s
        sorted_spec_names.join(", ")
      end

      def dependencies
        @dependencies ||= @specs.flat_map(&:expanded_dependencies).uniq.sort
      end

      def ==(other)
        sorted_spec_names == other.sorted_spec_names
      end

      def merge(other)
        return false unless equivalent?(other)

        @specs |= other.specs

        true
      end

      protected

      def sorted_spec_names
        @specs.map(&:full_name).sort
      end

      private

      def equivalent?(other)
        name == other.name && version == other.version && source == other.source && dependencies == other.dependencies
      end

      def exemplary_spec
        @specs.first
      end
    end
  end
end
