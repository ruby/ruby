# frozen_string_literal: true
require_relative "helper"

class TestGemBundlerVersionFinder < Gem::TestCase
  def setup
    super

    @argv = ARGV.dup
    @dollar_0 = $0
    without_any_upwards_gemfiles
  end

  def teardown
    ARGV.replace @argv
    $0 = @dollar_0

    super
  end

  def bvf
    Gem::BundlerVersionFinder
  end

  def test_bundler_version_defaults_to_nil
    assert_nil bvf.bundler_version
  end

  def test_bundler_version_with_env_var
    ENV["BUNDLER_VERSION"] = "1.1.1.1"
    assert_equal v("1.1.1.1"), bvf.bundler_version
  end

  def test_bundler_version_with_bundle_update_bundler
    ARGV.replace %w[update --bundler]
    assert_nil bvf.bundler_version
    $0 = "/foo/bar/bundle"
    assert_nil bvf.bundler_version
    ARGV.replace %w[update --bundler=1.1.1.1 gem_name]
    assert_equal v("1.1.1.1"), bvf.bundler_version
    ARGV.replace %w[update --bundler 1.1.1.1 gem_name]
    assert_equal v("1.1.1.1"), bvf.bundler_version
    ARGV.replace %w[update --bundler\ 1.1.1.1 gem_name]
    assert_equal v("1.1.1.1"), bvf.bundler_version
    ARGV.replace %w[update --bundler\ 1.1.1.2 --bundler --bundler 1.1.1.1 gem_name]
    assert_equal v("1.1.1.1"), bvf.bundler_version
    $0 = "other"
    assert_nil bvf.bundler_version
  end

  def test_bundler_version_with_lockfile
    bvf.stub(:lockfile_contents, "") do
      assert_nil bvf.bundler_version
    end
    bvf.stub(:lockfile_contents, "\n\nBUNDLED WITH\n   1.1.1.1\n") do
      assert_equal v("1.1.1.1"), bvf.bundler_version
    end
    bvf.stub(:lockfile_contents, "\n\nBUNDLED WITH\n   fjdkslfjdkslfjsldk\n") do
      assert_nil bvf.bundler_version
    end
  end

  def test_bundler_version
    assert_nil bvf.bundler_version
    bvf.stub(:lockfile_contents, "\n\nBUNDLED WITH\n   1.1.1.1\n") do
      assert_equal "1.1.1.1", bvf.bundler_version.to_s

      $0 = "bundle"
      ARGV.replace %w[update --bundler]
      assert_nil bvf.bundler_version

      ARGV.replace %w[update --bundler=1.1.1.2]
      assert_equal "1.1.1.2",  bvf.bundler_version.to_s

      ENV["BUNDLER_VERSION"] = "1.1.1.3"
      assert_equal "1.1.1.3", bvf.bundler_version.to_s
    end
  end

  def test_deleted_directory
    pend "Cannot perform this test on windows" if win_platform?
    pend "Cannot perform this test on Solaris" if RUBY_PLATFORM.include?("solaris")
    require "tmpdir"

    orig_dir = Dir.pwd

    begin
      Dir.mktmpdir("some_dir") do |dir|
        Dir.chdir(dir)
      end
    ensure
      Dir.chdir(orig_dir)
    end

    assert_nil bvf.bundler_version
  end

  def test_prioritize
    versions = %w[1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3 3.a 3.0 3.1.1]
    specs = versions.map {|v| util_spec("bundler", v) }

    assert_equal %w[1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3 3.a 3.0 3.1.1], util_prioritize_specs(specs)

    bvf.stub(:bundler_version, v("2.1.1.1")) do
      assert_equal %w[1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3 3.a 3.0 3.1.1], util_prioritize_specs(specs)
    end
    bvf.stub(:bundler_version, v("1.1.1.1")) do
      assert_equal %w[1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3 3.a 3.0 3.1.1], util_prioritize_specs(specs)
    end
    bvf.stub(:bundler_version, v("1")) do
      assert_equal %w[1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3 3.a 3.0 3.1.1], util_prioritize_specs(specs)
    end
    bvf.stub(:bundler_version, v("2.a")) do
      assert_equal %w[2.a 1 1.0 1.0.1.1 2 2.0 2.1.1 3 3.a 3.0 3.1.1], util_prioritize_specs(specs)
    end
    bvf.stub(:bundler_version, v("3")) do
      assert_equal %w[3 1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3.a 3.0 3.1.1], util_prioritize_specs(specs)
    end
  end

  def util_prioritize_specs(specs)
    specs = specs.dup
    bvf.prioritize!(specs)
    specs.map(&:version).map(&:to_s)
  end
end
