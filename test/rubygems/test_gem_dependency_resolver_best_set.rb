require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverBestSet < Gem::TestCase

  def setup
    super

    @DR = Gem::DependencyResolver
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

end

