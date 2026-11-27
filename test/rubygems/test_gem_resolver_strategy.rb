# frozen_string_literal: true

require_relative "helper"

class TestGemResolverStrategy < Gem::TestCase
  # Minimal source that implements the two methods Strategy calls:
  #   all_versions_for(package) - returns versions in preference order
  #   versions_for(package, range) - returns versions matching a range
  #
  # Tracks call counts so we can assert on caching behavior.
  class StubSource
    attr_reader :versions_for_calls

    def initialize(versions_by_package)
      @versions_by_package = versions_by_package
      @versions_for_calls = 0
    end

    def all_versions_for(package)
      @versions_by_package.fetch(package.to_s, [])
    end

    def versions_for(package, range)
      @versions_for_calls += 1
      all = @versions_by_package.fetch(package.to_s, [])
      all.select {|v| range.include?(v) }
    end
  end

  def v(version_string)
    Gem::Version.new(version_string)
  end

  def make_package(name)
    Gem::PubGrub::Package.new(name)
  end

  def make_range_any
    Gem::PubGrub::VersionRange.any
  end

  # A range >= min (unbounded above)
  def make_range_gte(version)
    Gem::PubGrub::VersionRange.new(min: version, include_min: true)
  end

  # A range >= min AND < max
  def make_range_between(min, max)
    Gem::PubGrub::VersionRange.new(
      min: min, max: max,
      include_min: true, include_max: false
    )
  end

  def test_most_preferred_version_respects_all_versions_for_ordering
    # all_versions_for returns [2.0, 1.0, 3.0] - so 2.0 is most preferred
    # even though 3.0 is numerically highest.
    pkg = make_package("a")
    source = StubSource.new("a" => [v("2.0"), v("1.0"), v("3.0")])

    strategy = Gem::Resolver::Strategy.new(source)
    unsatisfied = { pkg => make_range_any }

    _package, version = strategy.next_package_and_version(unsatisfied)

    assert_equal v("2.0"), version
  end

  def test_picks_most_constrained_package
    # "a" has 3 matching versions, "b" has 1 matching version.
    # Strategy should pick "b" because it's more constrained.
    pkg_a = make_package("a")
    pkg_b = make_package("b")

    source = StubSource.new(
      "a" => [v("3.0"), v("2.0"), v("1.0")],
      "b" => [v("1.0")]
    )

    strategy = Gem::Resolver::Strategy.new(source)

    unsatisfied = {
      pkg_a => make_range_any,
      pkg_b => make_range_any,
    }

    package, _version = strategy.next_package_and_version(unsatisfied)

    assert_equal pkg_b, package
  end

  def test_picks_package_with_fewer_higher_versions_as_tiebreaker
    # Both "a" and "b" have 2 matching versions (so both get priority [1, ...]).
    # "a" has matching [2.0, 1.0] with higher (above range) = [] (0 higher)
    # "b" has matching [2.0, 1.0] with higher [3.0] (1 higher)
    # Tiebreaker: fewer higher versions wins, so "a" is picked.
    pkg_a = make_package("a")
    pkg_b = make_package("b")

    range = make_range_between(v("0.5"), v("2.5"))

    source = StubSource.new(
      "a" => [v("2.0"), v("1.0")],
      "b" => [v("3.0"), v("2.0"), v("1.0")]
    )

    strategy = Gem::Resolver::Strategy.new(source)

    unsatisfied = {
      pkg_a => range,
      pkg_b => range,
    }

    package, _version = strategy.next_package_and_version(unsatisfied)

    assert_equal pkg_a, package
  end

  def test_cache_prevents_redundant_versions_for_calls
    pkg = make_package("a")
    source = StubSource.new("a" => [v("2.0"), v("1.0")])

    strategy = Gem::Resolver::Strategy.new(source)

    range = make_range_any
    unsatisfied = { pkg => range }

    # First call: should call versions_for for matching + upper_invert + most_preferred
    strategy.next_package_and_version(unsatisfied)
    calls_after_first = source.versions_for_calls

    # Second call with same package+range: next_term_to_try_from should
    # hit the cache, so only most_preferred_version_of adds a call.
    strategy.next_package_and_version(unsatisfied)
    calls_after_second = source.versions_for_calls

    # The cached path saves the 2 calls in next_term_to_try_from,
    # so only the 1 call from most_preferred_version_of is added.
    assert_equal 1, calls_after_second - calls_after_first
  end

  def test_cache_is_keyed_by_package_and_range
    pkg = make_package("a")
    source = StubSource.new("a" => [v("3.0"), v("2.0"), v("1.0")])

    strategy = Gem::Resolver::Strategy.new(source)

    range_any = make_range_any
    range_gte = make_range_gte(v("2.0"))

    # First call with range_any
    strategy.next_package_and_version({ pkg => range_any })
    calls_after_first = source.versions_for_calls

    # Second call with different range - cache miss, so versions_for is called again
    strategy.next_package_and_version({ pkg => range_gte })
    calls_after_second = source.versions_for_calls

    # A cache miss means 2 new versions_for calls (matching + upper_invert)
    # plus 1 from most_preferred_version_of = 3 total new calls
    assert_equal 3, calls_after_second - calls_after_first
  end
end
