# frozen_string_literal: true

module Bundler
  class Resolver
    class Strategy
      def initialize(source)
        @source = source
      end

      def next_package_and_version(unsatisfied)
        package, range = next_term_to_try_from(unsatisfied)

        [package, most_preferred_version_of(package, range).first]
      end

      private

      def next_term_to_try_from(unsatisfied)
        unsatisfied.min_by do |package, range|
          matching_versions = @source.versions_for(package, range)
          higher_versions = @source.versions_for(package, range.upper_invert)

          [matching_versions.count <= 1 ? 0 : 1, higher_versions.count]
        end
      end

      def most_preferred_version_of(package, range)
        versions = @source.versions_for(package, range)

        # Conditional avoids (among other things) calling
        # sort_versions_by_preferred with the root package
        if versions.size > 1
          @source.sort_versions_by_preferred(package, versions)
        else
          versions
        end
      end
    end
  end
end
