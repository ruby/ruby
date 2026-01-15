# frozen_string_literal: true

require_relative "helper"

class TestGemResolverRequirementList < Gem::TestCase
  def setup
    super

    @list = Gem::Resolver::RequirementList.new
  end

  def test_each
    dep = Gem::Dependency.new "a", "= 1"
    req = Gem::Resolver::DependencyRequest.new(dep, nil)
    @list.add req

    assert_equal [req], @list.each.to_a
  end
end
