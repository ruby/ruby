# frozen_string_literal: true

require_relative "remote_fetcher"
require_relative "user_interaction"
require_relative "errors"
require_relative "text"
require_relative "name_tuple"

##
# SpecFetcher handles metadata updates from remote gem repositories.

class Gem::SpecFetcher
  include Gem::UserInteraction
  include Gem::Text

  ##
  # Cache of latest specs

  attr_reader :latest_specs # :nodoc:

  ##
  # Sources for this SpecFetcher

  attr_reader :sources # :nodoc:

  ##
  # Cache of all released specs

  attr_reader :specs # :nodoc:

  ##
  # Cache of prerelease specs

  attr_reader :prerelease_specs # :nodoc:

  @fetcher = nil

  ##
  # Default fetcher instance.  Use this instead of ::new to reduce object
  # allocation.

  def self.fetcher
    @fetcher ||= new
  end

  def self.fetcher=(fetcher) # :nodoc:
    @fetcher = fetcher
  end

  ##
  # Creates a new SpecFetcher.  Ordinarily you want to use the default fetcher
  # from Gem::SpecFetcher::fetcher which uses the Gem.sources.
  #
  # If you need to retrieve specifications from a different +source+, you can
  # send it as an argument.

  def initialize(sources = nil)
    @sources = sources || Gem.sources

    @update_cache =
      begin
        File.stat(Gem.user_home).uid == Process.uid
      rescue Errno::EACCES, Errno::ENOENT
        false
      end

    @specs = {}
    @latest_specs = {}
    @prerelease_specs = {}

    @caches = {
      latest: @latest_specs,
      prerelease: @prerelease_specs,
      released: @specs,
    }

    @fetcher = Gem::RemoteFetcher.fetcher
  end

  ##
  #
  # Find and fetch gem name tuples that match +dependency+.
  #
  # If +matching_platform+ is false, gems for all platforms are returned.

  def search_for_dependency(dependency, matching_platform=true)
    found = {}

    rejected_specs = {}

    list, errors = available_specs(dependency.identity)

    list.each do |source, specs|
      if dependency.name.is_a?(String) && specs.respond_to?(:bsearch)
        start_index = (0...specs.length).bsearch {|i| specs[i].name >= dependency.name }
        end_index   = (0...specs.length).bsearch {|i| specs[i].name > dependency.name }
        specs = specs[start_index...end_index] if start_index && end_index
      end

      found[source] = specs.select do |tup|
        if dependency.match?(tup)
          if matching_platform && !Gem::Platform.match_gem?(tup.platform, tup.name)
            pm = (
              rejected_specs[dependency] ||= \
                Gem::PlatformMismatch.new(tup.name, tup.version))
            pm.add_platform tup.platform
            false
          else
            true
          end
        end
      end
    end

    errors += rejected_specs.values

    tuples = []

    found.each do |source, specs|
      specs.each do |s|
        tuples << [s, source]
      end
    end

    tuples = tuples.sort_by {|x| x[0].version }

    [tuples, errors]
  end

  ##
  # Return all gem name tuples who's names match +obj+

  def detect(type=:complete)
    tuples = []

    list, _ = available_specs(type)
    list.each do |source, specs|
      specs.each do |tup|
        if yield(tup)
          tuples << [tup, source]
        end
      end
    end

    tuples
  end

  ##
  # Find and fetch specs that match +dependency+.
  #
  # If +matching_platform+ is false, gems for all platforms are returned.

  def spec_for_dependency(dependency, matching_platform=true)
    tuples, errors = search_for_dependency(dependency, matching_platform)

    specs = []
    tuples.each do |tup, source|
      spec = source.fetch_spec(tup)
    rescue Gem::RemoteFetcher::FetchError => e
      errors << Gem::SourceFetchProblem.new(source, e)
    else
      specs << [spec, source]
    end

    [specs, errors]
  end

  ##
  # Suggests gems based on the supplied +gem_name+. Returns an array of
  # alternative gem names.

  def suggest_gems_from_name(gem_name, type = :latest, num_results = 5)
    gem_name = gem_name.downcase.tr("_-", "")

    # All results for 3-character-or-shorter (minus hyphens/underscores) gem
    # names get rejected, so we just return an empty array immediately instead.
    return [] if gem_name.length <= 3

    max   = gem_name.size / 2
    names = available_specs(type).first.values.flatten(1)

    min_length = gem_name.length - max
    max_length = gem_name.length + max

    gem_name_with_postfix = "#{gem_name}ruby"
    gem_name_with_prefix = "ruby#{gem_name}"

    matches = names.filter_map do |n|
      len = n.name.length
      # If the gem doesn't support the current platform, bail early.
      next unless n.match_platform?

      # If the length is min_length or shorter, we've done `max` deletions.
      # This would be rejected later, so we skip it for performance.
      next if len <= min_length

      # The candidate name, normalized the same as gem_name.
      normalized_name = n.name.downcase
      normalized_name.tr!("_-", "")

      # If the gem is "{NAME}-ruby" and "ruby-{NAME}", we want to return it.
      # But we already removed hyphens, so we check "{NAME}ruby" and "ruby{NAME}".
      next [n.name, 0] if normalized_name == gem_name_with_postfix
      next [n.name, 0] if normalized_name == gem_name_with_prefix

      # If the length is max_length or longer, we've done `max` insertions.
      # This would be rejected later, so we skip it for performance.
      next if len >= max_length

      # If we found an exact match (after stripping underscores and hyphens),
      # that's our most likely candidate.
      # Return it immediately, and skip the rest of the loop.
      return [n.name] if normalized_name == gem_name

      distance = levenshtein_distance gem_name, normalized_name

      # Skip current candidate, if the edit distance is greater than allowed.
      next if distance >= max

      # If all else fails, return the name and the calculated distance.
      [n.name, distance]
    end

    matches = if matches.empty? && type != :prerelease
      suggest_gems_from_name gem_name, :prerelease
    else
      matches.uniq.sort_by {|_name, dist| dist }
    end

    matches.map {|name, _dist| name }.uniq.first(num_results)
  end

  ##
  # Returns a list of gems available for each source in Gem::sources.
  #
  # +type+ can be one of 3 values:
  # :released   => Return the list of all released specs
  # :complete   => Return the list of all specs
  # :latest     => Return the list of only the highest version of each gem
  # :prerelease => Return the list of all prerelease only specs
  #

  def available_specs(type)
    errors = []
    list = {}

    @sources.each_source do |source|
      names = case type
              when :latest
                tuples_for source, :latest
              when :released
                tuples_for source, :released
              when :complete
                names =
                  tuples_for(source, :prerelease, true) +
                  tuples_for(source, :released)

                names.sort
              when :abs_latest
                names =
                  tuples_for(source, :prerelease, true) +
                  tuples_for(source, :latest)

                names.sort
              when :prerelease
                tuples_for(source, :prerelease)
              else
                raise Gem::Exception, "Unknown type - :#{type}"
      end
    rescue Gem::RemoteFetcher::FetchError => e
      errors << Gem::SourceFetchProblem.new(source, e)
    else
      list[source] = names
    end

    [list, errors]
  end

  ##
  # Retrieves NameTuples from +source+ of the given +type+ (:prerelease,
  # etc.).  If +gracefully_ignore+ is true, errors are ignored.

  def tuples_for(source, type, gracefully_ignore=false) # :nodoc:
    @caches[type][source.uri] ||=
      source.load_specs(type).sort_by(&:name)
  rescue Gem::RemoteFetcher::FetchError
    raise unless gracefully_ignore
    []
  end
end
