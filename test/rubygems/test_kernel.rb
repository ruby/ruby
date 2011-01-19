######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"

class TestKernel < RubyGemTestCase

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

  def test_gem_redundent
    assert gem('a', '= 1'), "Should load"
    refute gem('a', '= 1'), "Should not load"
    assert_equal 1, $:.select { |p| %r{a-1/lib} =~ p }.size
  end

  def test_gem_overlapping
    assert gem('a', '= 1'), "Should load"
    refute gem('a', '>= 1'), "Should not load"
    assert_equal 1, $:.select { |p| %r{a-1/lib} =~ p }.size
  end

  def test_gem_conflicting
    assert gem('a', '= 1'), "Should load"

    ex = assert_raises Gem::LoadError do
      gem 'a', '= 2'
    end

    assert_match(/activate a \(= 2, runtime\)/, ex.message)
    assert_match(/activated a-1/, ex.message)
    assert_equal 'a', ex.name
    assert_equal Gem::Requirement.new('= 2'), ex.requirement

    assert $:.any? { |p| %r{a-1/lib} =~ p }
    refute $:.any? { |p| %r{a-2/lib} =~ p }
  end

  def test_gem_not_adding_bin
    assert gem('a', '= 1'), "Should load"
    refute $:.any? { |p| %r{a-1/bin} =~ p }
  end
end
