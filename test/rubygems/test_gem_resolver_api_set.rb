require 'rubygems/test_case'

class TestGemResolverAPISet < Gem::TestCase

  def setup
    super

    @DR = Gem::Resolver
  end

  def test_initialize
    set = @DR::APISet.new

    assert_equal URI('https://rubygems.org/api/v1/dependencies'),
                 set.dep_uri
  end

  def test_initialize_uri
    set = @DR::APISet.new @gem_repo

    assert_equal URI('http://gems.example.com/'),
                 set.dep_uri
  end

end

