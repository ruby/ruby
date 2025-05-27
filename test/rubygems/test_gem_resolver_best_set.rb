# frozen_string_literal: true

require_relative "helper"

class TestGemResolverBestSet < Gem::TestCase
  def test_initialize
    set = Gem::Resolver::BestSet.new

    assert_empty set.sets
  end

  def test_find_all
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    api_uri = Gem::URI "#{@gem_repo}info/"

    @fetcher.data["#{api_uri}a"] = "---\n1  "

    set = Gem::Resolver::BestSet.new

    set.sets << Gem::Resolver::APISet.new(api_uri)

    dependency = dep "a", "~> 1"

    req = Gem::Resolver::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_equal %w[a-1], found.map(&:full_name)
  end

  def test_pick_sets_prerelease
    set = Gem::Resolver::BestSet.new
    set.prerelease = true

    set.pick_sets

    sets = set.sets

    assert_equal 1, sets.count

    source_set = sets.first
    assert_equal true, source_set.prerelease
  end

  def test_find_all_local
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
      fetcher.spec "a", 2
      fetcher.spec "b", 1
    end

    set = Gem::Resolver::BestSet.new
    set.remote = false

    dependency = dep "a", "~> 1"

    req = Gem::Resolver::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_empty found
  end

  def test_prefetch
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    set = Gem::Resolver::BestSet.new

    set.prefetch []

    refute_empty set.sets
  end

  def test_prefetch_local
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    set = Gem::Resolver::BestSet.new
    set.remote = false

    set.prefetch []

    assert_empty set.sets
  end
end
