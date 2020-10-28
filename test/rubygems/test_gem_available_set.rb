# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/available_set'
require 'rubygems/security'

class TestGemAvailableSet < Gem::TestCase
  def setup
    super

    @source = Gem::Source.new(@gem_repo)
  end

  def test_add_and_empty
    a1, _ = util_gem 'a', '1'

    set = Gem::AvailableSet.new
    assert set.empty?

    set.add a1, @source

    refute set.empty?

    assert_equal [a1], set.all_specs
  end

  def test_find_all
    a1,  a1_gem  = util_gem 'a', 1
    a1a, a1a_gem = util_gem 'a', '1.a'

    a1_source  = Gem::Source::SpecificFile.new a1_gem
    a1a_source = Gem::Source::SpecificFile.new a1a_gem

    set = Gem::AvailableSet.new
    set.add a1,  a1_source
    set.add a1a, a1a_source

    dep = Gem::Resolver::DependencyRequest.new dep('a'), nil

    assert_equal %w[a-1], set.find_all(dep).map {|spec| spec.full_name }

    dep = Gem::Resolver::DependencyRequest.new dep('a', '>= 0.a'), nil

    assert_equal %w[a-1 a-1.a],
                 set.find_all(dep).map {|spec| spec.full_name }.sort
  end

  def test_match_platform
    a1, _ = util_gem 'a', '1' do |g|
      g.platform = "something-weird-yep"
    end

    a1c, _ = util_gem 'a', '2' do |g|
      g.platform = Gem::Platform.local
    end

    a2, _ = util_gem 'a', '2'

    set = Gem::AvailableSet.new
    set.add a1, @source
    set.add a1c, @source
    set.add a2, @source

    set.match_platform!

    assert_equal [a1c, a2], set.all_specs
  end

  def test_best
    a1, _ = util_gem 'a', '1'
    a2, _ = util_gem 'a', '2'

    set = Gem::AvailableSet.new
    set.add a1, @source
    set.add a2, @source

    set.pick_best!

    assert_equal [a2], set.all_specs
  end

  def test_remove_installed_bang
    a1, _ = util_spec 'a', '1'
    install_specs a1

    a1.activate

    set = Gem::AvailableSet.new
    set.add a1, @source

    dep = Gem::Dependency.new "a", ">= 0"

    set.remove_installed! dep

    assert set.empty?
  end

  def test_sorted_normal_versions
    a1, _ = util_gem 'a', '1'
    a2, _ = util_gem 'a', '2'

    set = Gem::AvailableSet.new
    set.add a1, @source
    set.add a2, @source

    g = set.sorted

    assert_equal a2, g[0].spec
    assert_equal a1, g[1].spec
  end

  def test_sorted_respect_pre
    a1a, _ = util_gem 'a', '1.a'
    a1,  _ = util_gem 'a', '1'
    a2a, _ = util_gem 'a', '2.a'
    a2,  _ = util_gem 'a', '2'
    a3a, _ = util_gem 'a', '3.a'

    set = Gem::AvailableSet.new
    set.add a1, @source
    set.add a1a, @source
    set.add a3a, @source
    set.add a2a, @source
    set.add a2, @source

    g = set.sorted.map {|t| t.spec }

    assert_equal [a3a, a2, a2a, a1, a1a], g
  end
end
