# frozen_string_literal: true

require_relative "package"

module Bundler
  class Resolver
    class Base
      attr_reader :packages, :requirements, :source_requirements

      def initialize(source_requirements, dependencies, base, platforms, options)
        @source_requirements = source_requirements

        @base = base

        @packages = Hash.new do |hash, name|
          hash[name] = Package.new(name, platforms, **options)
        end

        @requirements = dependencies.map do |dep|
          dep_platforms = dep.gem_platforms(platforms)

          # Dependencies scoped to external platforms are ignored
          next if dep_platforms.empty?

          name = dep.name

          @packages[name] = Package.new(name, dep_platforms, **options.merge(:dependency => dep))

          dep
        end.compact
      end

      def [](name)
        @base[name]
      end

      def delete(incomplete_specs)
        incomplete_specs.each do |incomplete_spec|
          incomplete_spec.partially_complete_specs.each do |spec|
            @base.delete(spec)
          end
        end
      end

      def get_package(name)
        @packages[name]
      end

      def base_requirements
        @base_requirements ||= build_base_requirements
      end

      def unlock_names(names)
        names.each do |name|
          @base.delete_by_name(name)

          @base_requirements.delete(name)
        end
      end

      def include_prereleases(names)
        names.each do |name|
          get_package(name).consider_prereleases!
        end
      end

      private

      def build_base_requirements
        base_requirements = {}
        @base.each do |ls|
          req = Gem::Requirement.new(ls.version)
          base_requirements[ls.name] = req
        end
        base_requirements
      end
    end
  end
end
