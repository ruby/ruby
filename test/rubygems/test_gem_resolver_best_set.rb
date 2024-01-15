# frozen_string_literal: true

require_relative "helper"

class TestGemResolverBestSet < Gem::TestCase
  def test_initialize
    set = Gem::Resolver::BestSet.new

    assert_empty set.sets
  end

  def test_find_all_index
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
      fetcher.spec "a", 2
      fetcher.spec "b", 1
    end

    set = Gem::Resolver::BestSet.new

    dependency = dep "a", "~> 1"

    req = Gem::Resolver::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_equal %w[a-1], found.map(&:full_name)
  end

  def test_find_all_fallback
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    set = Gem::Resolver::BestSet.new

    api_uri = Gem::URI(@gem_repo)

    set.sets << Gem::Resolver::APISet.new(api_uri)

    dependency = dep "a", "~> 1"

    req = Gem::Resolver::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_equal %w[a-1], found.map(&:full_name)
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

  def test_replace_failed_api_set
    set = Gem::Resolver::BestSet.new

    api_uri = Gem::URI(@gem_repo) + "./info/"
    api_set = Gem::Resolver::APISet.new api_uri

    set.sets << api_set

    error_uri = api_uri + "a"

    error = Gem::RemoteFetcher::FetchError.new "bogus", error_uri

    set.replace_failed_api_set error

    assert_equal 1, set.sets.size

    refute_includes set.sets, api_set

    assert_kind_of Gem::Resolver::IndexSet, set.sets.first
  end

  def test_replace_failed_api_set_no_api_set
    set = Gem::Resolver::BestSet.new

    index_set = Gem::Resolver::IndexSet.new Gem::Source.new @gem_repo

    set.sets << index_set

    error = Gem::RemoteFetcher::FetchError.new "bogus", @gem_repo

    e = assert_raise Gem::RemoteFetcher::FetchError do
      set.replace_failed_api_set error
    end

    assert_equal error, e
  end

  def test_replace_failed_api_set_uri_with_credentials
    set = Gem::Resolver::BestSet.new

    api_uri = Gem::URI(@gem_repo) + "./info/"
    api_uri.user = "user"
    api_uri.password = "pass"
    api_set = Gem::Resolver::APISet.new api_uri

    set.sets << api_set

    error_uri = api_uri + "a"

    error = Gem::RemoteFetcher::FetchError.new "bogus", error_uri

    set.replace_failed_api_set error

    assert_equal 1, set.sets.size

    refute_includes set.sets, api_set

    assert_kind_of Gem::Resolver::IndexSet, set.sets.first
  end
end
