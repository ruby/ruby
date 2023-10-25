# frozen_string_literal: true

require_relative "helper"

class TestGemResolverIndexSet < Gem::TestCase
  def test_initialize
    set = Gem::Resolver::IndexSet.new

    fetcher = set.instance_variable_get :@f

    assert_same Gem::SpecFetcher.fetcher, fetcher
  end

  def test_initialize_source
    set = Gem::Resolver::IndexSet.new "http://alternate.example"

    fetcher = set.instance_variable_get :@f

    refute_same Gem::SpecFetcher.fetcher, fetcher

    refute_empty set.errors
  end

  def test_find_all
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
      fetcher.spec "a", 2
      fetcher.spec "b", 1
    end

    set = Gem::Resolver::IndexSet.new

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

    set = Gem::Resolver::IndexSet.new
    set.remote = false

    dependency = dep "a", "~> 1"

    req = Gem::Resolver::DependencyRequest.new dependency, nil

    assert_empty set.find_all req
  end

  def test_find_all_prerelease
    spec_fetcher do |fetcher|
      fetcher.spec "a", "1.a"
    end

    set = Gem::Resolver::IndexSet.new

    dependency = dep "a"

    req = Gem::Resolver::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_empty found

    dependency.prerelease = true

    req = Gem::Resolver::DependencyRequest.new dependency, nil

    found = set.find_all req

    assert_equal %w[a-1.a], found.map(&:full_name)
  end
end
