# frozen_string_literal: true

module Bundler
  class CompactIndexClient
    class GemParser
      def parse(line)
        version_and_platform, rest = line.split(" ", 2)
        version, platform = version_and_platform.split("-", 2)
        dependencies, requirements = rest.split("|", 2) if rest
        dependencies = dependencies ? parse_dependencies(dependencies) : []
        requirements = requirements ? parse_requirements(requirements) : []
        [version, platform, dependencies, requirements]
      end

    private

      def parse_dependencies(raw_dependencies)
        raw_dependencies.split(",").map {|d| parse_dependency(d) }
      end

      def parse_dependency(raw_dependency)
        dependency = raw_dependency.split(":")
        dependency[-1] = dependency[-1].split("&") if dependency.size > 1
        dependency
      end

      # Parse the following format:
      #
      #   line = "checksum:#{checksum}"
      #   line << ",ruby:#{ruby_version}" if ruby_version && ruby_version != ">= 0"
      #   line << ",rubygems:#{rubygems_version}" if rubygems_version && rubygems_version != ">= 0"
      #
      # See compact_index/gem_version.rb for details.
      #
      # We can't use parse_dependencies for requirements because "," in
      # ruby_version and rubygems_version isn't escaped as "&". For example,
      # "checksum:XXX,ruby:>=2.2, < 2.7.dev" can't be parsed as expected.
      def parse_requirements(raw_requirements)
        requirements = []
        checksum = raw_requirements.match(/\A(checksum):([^,]+)/)
        if checksum
          requirements << [checksum[1], [checksum[2]]]
          raw_requirements = checksum.post_match
          if raw_requirements.start_with?(",")
            raw_requirements = raw_requirements[1..-1]
          end
        end
        rubygems = raw_requirements.match(/(rubygems):(.+)\z/)
        if rubygems
          raw_requirements = rubygems.pre_match
          if raw_requirements.start_with?(",")
            raw_requirements = raw_requirements[1..-1]
          end
        end
        ruby = raw_requirements.match(/\A(ruby):(.+)\z/)
        if ruby
          requirements << [ruby[1], ruby[2].split(/\s*,\s*/)]
        end
        if rubygems
          requirements << [rubygems[1], rubygems[2].split(/\s*,\s*/)]
        end
        requirements
      end
    end
  end
end
