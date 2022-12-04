# frozen_string_literal: true

module Bundler
  # This class contains all of the logic for determining the next version of a
  # Gem to update to based on the requested level (patch, minor, major).
  # Primarily designed to work with Resolver which will provide it the list of
  # available dependency versions as found in its index, before returning it to
  # to the resolution engine to select the best version.
  class GemVersionPromoter
    attr_reader :level

    # By default, strict is false, meaning every available version of a gem
    # is returned from sort_versions. The order gives preference to the
    # requested level (:patch, :minor, :major) but in complicated requirement
    # cases some gems will by necessity by promoted past the requested level,
    # or even reverted to older versions.
    #
    # If strict is set to true, the results from sort_versions will be
    # truncated, eliminating any version outside the current level scope.
    # This can lead to unexpected outcomes or even VersionConflict exceptions
    # that report a version of a gem not existing for versions that indeed do
    # existing in the referenced source.
    attr_accessor :strict

    # Creates a GemVersionPromoter instance.
    #
    # @return [GemVersionPromoter]
    def initialize
      @level = :major
      @strict = false
    end

    # @param value [Symbol] One of three Symbols: :major, :minor or :patch.
    def level=(value)
      v = case value
          when String, Symbol
            value.to_sym
      end

      raise ArgumentError, "Unexpected level #{v}. Must be :major, :minor or :patch" unless [:major, :minor, :patch].include?(v)
      @level = v
    end

    # Given a Resolver::Package and an Array of Specifications of available
    # versions for a gem, this method will return the Array of Specifications
    # sorted (and possibly truncated if strict is true) in an order to give
    # preference to the current level (:major, :minor or :patch) when resolution
    # is deciding what versions best resolve all dependencies in the bundle.
    # @param package [Resolver::Package] The package being resolved.
    # @param specs [Specification] An array of Specifications for the package.
    # @return [Specification] A new instance of the Specification Array sorted and
    #    possibly filtered.
    def sort_versions(package, specs)
      specs = filter_dep_specs(specs, package) if strict

      sort_dep_specs(specs, package)
    end

    # @return [bool] Convenience method for testing value of level variable.
    def major?
      level == :major
    end

    # @return [bool] Convenience method for testing value of level variable.
    def minor?
      level == :minor
    end

    private

    def filter_dep_specs(specs, package)
      locked_version = package.locked_version

      specs.select do |spec|
        if locked_version && !major?
          gsv = spec.version
          lsv = locked_version

          must_match = minor? ? [0] : [0, 1]

          matches = must_match.map {|idx| gsv.segments[idx] == lsv.segments[idx] }
          matches.uniq == [true] ? (gsv >= lsv) : false
        else
          true
        end
      end
    end

    def sort_dep_specs(specs, package)
      locked_version = package.locked_version

      result = specs.sort do |a, b|
        unless locked_version && package.prerelease_specified?
          a_pre = a.prerelease?
          b_pre = b.prerelease?

          next -1 if a_pre && !b_pre
          next  1 if b_pre && !a_pre
        end

        if major?
          a <=> b
        elsif either_version_older_than_locked(a, b, locked_version)
          a <=> b
        elsif segments_do_not_match(a, b, :major)
          b <=> a
        elsif !minor? && segments_do_not_match(a, b, :minor)
          b <=> a
        else
          a <=> b
        end
      end
      post_sort(result, package.unlock?, locked_version)
    end

    def either_version_older_than_locked(a, b, locked_version)
      locked_version && (a.version < locked_version || b.version < locked_version)
    end

    def segments_do_not_match(a, b, level)
      index = [:major, :minor].index(level)
      a.segments[index] != b.segments[index]
    end

    # Specific version moves can't always reliably be done during sorting
    # as not all elements are compared against each other.
    def post_sort(result, unlock, locked_version)
      # default :major behavior in Bundler does not do this
      return result if major?
      if unlock || locked_version.nil?
        result
      else
        move_version_to_end(result, locked_version)
      end
    end

    def move_version_to_end(result, version)
      move, keep = result.partition {|s| s.version.to_s == version.to_s }
      keep.concat(move)
    end
  end
end
