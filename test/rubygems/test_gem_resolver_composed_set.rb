require 'rubygems/test_case'

class TestGemResolverComposedSet < Gem::TestCase

  def test_remote_equals
    best_set    = Gem::Resolver::BestSet.new
    current_set = Gem::Resolver::CurrentSet.new

    set = Gem::Resolver::ComposedSet.new best_set, current_set

    set.remote = false

    refute best_set.remote?
    refute current_set.remote?
  end

end

