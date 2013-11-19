require 'rubygems/test_case'

class TestGemResolverRequirementList < Gem::TestCase

  def setup
    super

    @list = Gem::Resolver::RequirementList.new
  end

  def test_each
    @list.add 1
    @list.add 2

    assert_equal [1, 2], @list.each.to_a
  end

end

