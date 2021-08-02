# frozen_string_literal: true
require_relative 'helper'

class TestGemResolverIndexSet < Gem::TestCase
  def setup
    super

    @DR = Gem::Resolver
  end

  def test_initialize
    set = @DR::IndexSet.new

    fetcher = set.instance_variable_get :@f

    assert_same Gem::SpecFetcher.fetcher, fetcher
  end

  def test_initialize_source
    set = @DR::IndexSet.new 'http://alternate.example'

    fetcher = set.instance_variable_get :@f

    refute_same Gem::SpecFetcher.fetcher, fetcher

    refute_empty set.errors
  end

  def test_find_all
    spec_fetcher do |fetcher|
      fetcher.spec 'a', 1
      fetcher.spec 'a', 2
      fetcher.spec 'b', 1
    end

    set = @DR::IndexSet.new

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

    set = @DR::IndexSet.new
    set.remote = false

    dependency = dep 'a', '~> 1'

    req = @DR::DependencyRequest.new dependency, nil

    assert_empty set.find_all req
  end

  def test_find_all_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec 'a', '1.a'
    end

    set = @DR::IndexSet.new

    dependency = dep 'a'

    req = @DR::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_empty found

    dependency.prerelease = true

    req = @DR::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_equal %w[a-1.a], found.map {|s| s.full_name }
  end
end
