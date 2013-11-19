require 'rubygems/test_case'

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
  end

end

