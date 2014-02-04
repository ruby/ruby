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

    assert_equal %w[a-1], found.map { |s| s.full_name }
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

end

