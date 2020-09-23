# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemResolverBestSet < Gem::TestCase

  def setup
    super

    @DR = Gem::Resolver
  end

  def test_initialize
    set = @DR::BestSet.new

    assert_empty set.sets
  end

  def test_find_all_index
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'b', 1
    end

    set = @DR::BestSet.new

    dependency = dep 'a', '~> 1'

    req = @DR::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_equal %w[a-1], found.map {|s| s.full_name }
  end

  def test_find_all_fallback
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
    end

    set = @DR::BestSet.new

    api_uri = URI(@gem_repo) + './api/v1/dependencies'

    set.sets << Gem::Resolver::APISet.new(api_uri)

    dependency = dep 'a', '~> 1'

    req = @DR::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_equal %w[a-1], found.map {|s| s.full_name }
  end

  def test_find_all_local
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'b', 1
    end

    set = @DR::BestSet.new
    set.remote = false

    dependency = dep 'a', '~> 1'

    req = @DR::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_empty found
  end

  def test_prefetch
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
    end

    set = @DR::BestSet.new

    set.prefetch []

    refute_empty set.sets
  end

  def test_prefetch_local
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
    end

    set = @DR::BestSet.new
    set.remote = false

    set.prefetch []

    assert_empty set.sets
  end

  def test_replace_failed_api_set
    set = @DR::BestSet.new

    api_uri = URI(@gem_repo) + './api/v1/dependencies'
    api_set = Gem::Resolver::APISet.new api_uri

    set.sets << api_set

    error_uri = api_uri + '?gems=a'

    error = Gem::RemoteFetcher::FetchError.new 'bogus', error_uri

    set.replace_failed_api_set error

    assert_equal 1, set.sets.size

    refute_includes set.sets, api_set

    assert_kind_of Gem::Resolver::IndexSet, set.sets.first
  end

  def test_replace_failed_api_set_no_api_set
    set = @DR::BestSet.new

    index_set = Gem::Resolver::IndexSet.new Gem::Source.new @gem_repo

    set.sets << index_set

    error = Gem::RemoteFetcher::FetchError.new 'bogus', @gem_repo

    e = assert_raises Gem::RemoteFetcher::FetchError do
      set.replace_failed_api_set error
    end

    assert_equal error, e
  end

end
