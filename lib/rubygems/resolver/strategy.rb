# frozen_string_literal: true

# Custom PubGrub strategy with caching for version selection.
# Modeled after Bundler's strategy to avoid redundant versions_for
# calls during the solver's package selection loop.

class Gem::Resolver::Strategy
  def initialize(source)
    @source = source
    @package_priority_cache = {}

    @version_indexes = Hash.new do |h, k|
      if Gem::PubGrub::Package.root?(k)
        h[k] = { Gem::PubGrub::Package.root_version => 0 }
      else
        h[k] = @source.all_versions_for(k).each.with_index.to_h
      end
    end
  end

  def next_package_and_version(unsatisfied)
    package, range = next_term_to_try_from(unsatisfied)
    [package, most_preferred_version_of(package, range)]
  end

  private

  def most_preferred_version_of(package, range)
    versions = @source.versions_for(package, range)
    indexes = @version_indexes[package]
    versions.min_by {|version| indexes[version] || Float::INFINITY }
  end

  def next_term_to_try_from(unsatisfied)
    unsatisfied.min_by do |package, range|
      @package_priority_cache[[package, range]] ||= begin
        matching_versions = @source.versions_for(package, range)
        higher_versions = @source.versions_for(package, range.upper_invert)

        [matching_versions.count <= 1 ? 0 : 1, higher_versions.count]
      end
    end
  end
end
