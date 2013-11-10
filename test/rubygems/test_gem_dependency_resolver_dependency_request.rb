require 'rubygems/test_case'

class TestGemDependencyResolverDependencyRequest < Gem::TestCase

  def setup
    super

    @DR = Gem::DependencyResolver::DependencyRequest
  end

  def test_requirement
    dependency = dep 'a', '>= 1'

    dr = @DR.new dependency, nil

    assert_equal dependency, dr.dependency
  end

end

