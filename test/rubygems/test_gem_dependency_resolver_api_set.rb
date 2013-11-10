require 'rubygems/test_case'
require 'rubygems/dependency_resolver'

class TestGemDependencyResolverAPISet < Gem::TestCase

  def setup
    super

    @DR = Gem::DependencyResolver
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

