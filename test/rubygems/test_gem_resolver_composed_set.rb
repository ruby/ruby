# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemResolverComposedSet < Gem::TestCase

  def test_errors
    index_set   = Gem::Resolver::IndexSet.new
    current_set = Gem::Resolver::CurrentSet.new

    set = Gem::Resolver::ComposedSet.new index_set, current_set

    set.instance_variable_get(:@errors) << :a
    current_set.errors << :b

    assert_includes set.errors, :a
    assert_includes set.errors, :b
    assert_includes set.errors, index_set.errors.first
  end

  def test_prerelease_equals
    best_set    = Gem::Resolver::BestSet.new
    current_set = Gem::Resolver::CurrentSet.new

    set = Gem::Resolver::ComposedSet.new best_set, current_set

    set.prerelease = true

    assert set.prerelease
    assert best_set.prerelease
    assert current_set.prerelease
  end

  def test_remote_equals
    best_set    = Gem::Resolver::BestSet.new
    current_set = Gem::Resolver::CurrentSet.new

    set = Gem::Resolver::ComposedSet.new best_set, current_set

    set.remote = false

    refute best_set.remote?
    refute current_set.remote?
  end

end

