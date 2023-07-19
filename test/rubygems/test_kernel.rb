# frozen_string_literal: true
require_relative "helper"

class TestGemKernel < Gem::TestCase
  def setup
    super

    util_make_gems

    without_any_upwards_gemfiles
  end

  def test_gem
    assert gem("a", "= 1"), "Should load"
    assert $:.any? {|p| p.include?("a-1/lib") }
  end

  def test_gem_default
    assert gem("a", ">= 0")

    assert_equal @a2, Gem.loaded_specs["a"]
  end

  def test_gem_default_re_gem
    assert gem("a", "=1")

    refute gem("a", ">= 0")

    assert_equal @a1, Gem.loaded_specs["a"]
  end

  def test_gem_re_gem_mismatch
    assert gem("a", "=1")

    assert_raise Gem::LoadError do
      gem("a", "= 2")
    end

    assert_equal @a1, Gem.loaded_specs["a"]
  end

  def test_gem_redundant
    assert gem("a", "= 1"), "Should load"
    refute gem("a", "= 1"), "Should not load"
    assert_equal 1, $:.select {|p| p.include?("a-1/lib") }.size
  end

  def test_gem_overlapping
    assert gem("a", "= 1"), "Should load"
    refute gem("a", ">= 1"), "Should not load"
    assert_equal 1, $:.select {|p| p.include?("a-1/lib") }.size
  end

  def test_gem_prerelease
    quick_gem "d", "1.1.a"
    refute gem("d", ">= 1"),   "release requirement must not load prerelease"
    assert gem("d", ">= 1.a"), "prerelease requirement may load prerelease"
  end

  def test_gem_env_req
    ENV["GEM_REQUIREMENT_A"] = "~> 2.0"
    assert_raise(Gem::MissingSpecVersionError) { gem("a", "= 1") }
    assert gem("a", "> 1")
    assert_equal @a2, Gem.loaded_specs["a"]
  end

  def test_gem_conflicting
    assert gem("a", "= 1"), "Should load"

    ex = assert_raise Gem::LoadError do
      gem "a", "= 2"
    end

    assert_equal "can't activate a-2, already activated a-1", ex.message
    assert_match(/activated a-1/, ex.message)
    assert_equal "a", ex.name

    assert $:.any? {|p| p.include?("a-1/lib") }
    refute $:.any? {|p| p.include?("a-2/lib") }
  end

  def test_gem_not_adding_bin
    assert gem("a", "= 1"), "Should load"
    refute $:.any? {|p| p.include?("a-1/bin") }
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
    quick_gem "bundler", "1"
    quick_gem "bundler", "2.a"

    assert gem("bundler")
    assert $:.any? {|p| p.include?("bundler-1/lib") }
  end

  def test_gem_bundler_inferred_bundler_version
    require "rubygems/bundler_version_finder"

    Gem::BundlerVersionFinder.stub(:bundler_version, Gem::Version.new("1")) do
      quick_gem "bundler", "1"
      quick_gem "bundler", "2.a"

      assert gem("bundler", ">= 0.a")
      assert $:.any? {|p| p.include?("bundler-1/lib") }
    end
  end
end
