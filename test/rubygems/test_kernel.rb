# frozen_string_literal: true
require 'rubygems/test_case'

class TestKernel < Gem::TestCase

  def setup
    super

    @old_path = $:.dup

    util_make_gems
  end

  def teardown
    super

    $:.replace @old_path
  end

  def test_gem
    assert gem('a', '= 1'), "Should load"
    assert $:.any? { |p| %r{a-1/lib} =~ p }
  end

  def test_gem_default
    assert gem('a', '>= 0')

    assert_equal @a2, Gem.loaded_specs['a']
  end

  def test_gem_default_re_gem
    assert gem('a', '=1')

    refute gem('a', '>= 0')

    assert_equal @a1, Gem.loaded_specs['a']
  end

  def test_gem_re_gem_mismatch
    assert gem('a', '=1')

    assert_raises Gem::LoadError do
      gem('a', '= 2')
    end

    assert_equal @a1, Gem.loaded_specs['a']
  end

  def test_gem_redundant
    assert gem('a', '= 1'), "Should load"
    refute gem('a', '= 1'), "Should not load"
    assert_equal 1, $:.select { |p| %r{a-1/lib} =~ p }.size
  end

  def test_gem_overlapping
    assert gem('a', '= 1'), "Should load"
    refute gem('a', '>= 1'), "Should not load"
    assert_equal 1, $:.select { |p| %r{a-1/lib} =~ p }.size
  end

  def test_gem_prerelease
    quick_gem 'd', '1.1.a'
    refute gem('d', '>= 1'),   'release requirement must not load prerelease'
    assert gem('d', '>= 1.a'), 'prerelease requirement may load prerelease'
  end

  def test_gem_env_req
    ENV["GEM_REQUIREMENT_A"] = '~> 2.0'
    assert_raises(Gem::MissingSpecVersionError) { gem('a', '= 1') }
    assert gem('a', '> 1')
    assert_equal @a2, Gem.loaded_specs['a']
  end

  def test_gem_conflicting
    assert gem('a', '= 1'), "Should load"

    ex = assert_raises Gem::LoadError do
      gem 'a', '= 2'
    end

    assert_equal "can't activate a-2, already activated a-1", ex.message
    assert_match(/activated a-1/, ex.message)
    assert_equal 'a', ex.name

    assert $:.any? { |p| %r{a-1/lib} =~ p }
    refute $:.any? { |p| %r{a-2/lib} =~ p }
  end

  def test_gem_not_adding_bin
    assert gem('a', '= 1'), "Should load"
    refute $:.any? { |p| %r{a-1/bin} =~ p }
  end
end
