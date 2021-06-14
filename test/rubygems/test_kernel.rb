# frozen_string_literal: true
require 'rubygems/test_case'

class TestKernel < Gem::TestCase
  def setup
    super

    @old_path = $:.dup

    util_make_gems

    without_any_upwards_gemfiles
  end

  def teardown
    super

    $:.replace @old_path
  end

  def test_gem
    assert gem('a', '= 1'), "Should load"
    assert $:.any? {|p| %r{a-1/lib} =~ p }
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

    assert_raise Gem::LoadError do
      gem('a', '= 2')
    end

    assert_equal @a1, Gem.loaded_specs['a']
  end

  def test_gem_redundant
    assert gem('a', '= 1'), "Should load"
    refute gem('a', '= 1'), "Should not load"
    assert_equal 1, $:.select {|p| %r{a-1/lib} =~ p }.size
  end

  def test_gem_overlapping
    assert gem('a', '= 1'), "Should load"
    refute gem('a', '>= 1'), "Should not load"
    assert_equal 1, $:.select {|p| %r{a-1/lib} =~ p }.size
  end

  def test_gem_prerelease
    quick_gem 'd', '1.1.a'
    refute gem('d', '>= 1'),   'release requirement must not load prerelease'
    assert gem('d', '>= 1.a'), 'prerelease requirement may load prerelease'
  end

  def test_gem_env_req
    ENV["GEM_REQUIREMENT_A"] = '~> 2.0'
    assert_raise(Gem::MissingSpecVersionError) { gem('a', '= 1') }
    assert gem('a', '> 1')
    assert_equal @a2, Gem.loaded_specs['a']
  end

  def test_gem_conflicting
    assert gem('a', '= 1'), "Should load"

    ex = assert_raise Gem::LoadError do
      gem 'a', '= 2'
    end

    assert_equal "can't activate a-2, already activated a-1", ex.message
    assert_match(/activated a-1/, ex.message)
    assert_equal 'a', ex.name

    assert $:.any? {|p| %r{a-1/lib} =~ p }
    refute $:.any? {|p| %r{a-2/lib} =~ p }
  end

  def test_gem_not_adding_bin
    assert gem('a', '= 1'), "Should load"
    refute $:.any? {|p| %r{a-1/bin} =~ p }
  end

  def test_gem_failing_inside_require_doesnt_cause_double_exceptions
    File.write("activate.rb", "gem('a', '= 999')\n")

    require "open3"

    output, _ = Open3.capture2e(
      { "GEM_HOME" => Gem.paths.home },
      *ruby_with_rubygems_in_load_path,
      "-r",
      "./activate.rb"
    )

    load_errors = output.split("\n").select {|line| line.include?("Could not find") }

    assert_equal 1, load_errors.size
  end

  def test_gem_bundler
    quick_gem 'bundler', '1'
    quick_gem 'bundler', '2.a'

    assert gem('bundler')
    assert $:.any? {|p| %r{bundler-1/lib} =~ p }
  end

  def test_gem_bundler_missing_bundler_version
    Gem::BundlerVersionFinder.stub(:bundler_version_with_reason, ["55", "reason"]) do
      quick_gem 'bundler', '1'
      quick_gem 'bundler', '2.a'

      e = assert_raise Gem::MissingSpecVersionError do
        gem('bundler')
      end
      assert_match "Could not find 'bundler' (55) required by reason.", e.message
    end
  end

  def test_gem_bundler_inferred_bundler_version
    Gem::BundlerVersionFinder.stub(:bundler_version_with_reason, ["1", "reason"]) do
      quick_gem 'bundler', '1'
      quick_gem 'bundler', '2.a'

      assert gem('bundler', '>= 0.a')
      assert $:.any? {|p| %r{bundler-1/lib} =~ p }
    end
  end
end
