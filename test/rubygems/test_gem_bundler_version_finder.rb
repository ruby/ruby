# frozen_string_literal: true
require 'rubygems/test_case'

class TestGemBundlerVersionFinder < Gem::TestCase

  def setup
    super

    @argv = ARGV.dup
    @env = ENV.to_hash.clone
    ENV.delete("BUNDLER_VERSION")
    @dollar_0 = $0
  end

  def teardown
    ARGV.replace @argv
    ENV.replace @env
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
    bvf.stub(:lockfile_contents, [nil, ""]) do
      assert_nil bvf.bundler_version
    end
    bvf.stub(:lockfile_contents, [nil, "\n\nBUNDLED WITH\n   1.1.1.1\n"]) do
      assert_equal v("1.1.1.1"), bvf.bundler_version
    end
    bvf.stub(:lockfile_contents, [nil, "\n\nBUNDLED WITH\n   fjdkslfjdkslfjsldk\n"]) do
      assert_nil bvf.bundler_version
    end
  end

  def test_bundler_version_with_reason
    assert_nil bvf.bundler_version_with_reason
    bvf.stub(:lockfile_contents, [nil, "\n\nBUNDLED WITH\n   1.1.1.1\n"]) do
      assert_equal ["1.1.1.1", "your lockfile"], bvf.bundler_version_with_reason

      $0 = "bundle"
      ARGV.replace %w[update --bundler]
      assert_nil bvf.bundler_version_with_reason
      ARGV.replace %w[update --bundler=1.1.1.2]
      assert_equal ["1.1.1.2", "`bundle update --bundler`"], bvf.bundler_version_with_reason

      ENV["BUNDLER_VERSION"] = "1.1.1.3"
      assert_equal ["1.1.1.3", "`$BUNDLER_VERSION`"], bvf.bundler_version_with_reason
    end
  end

  def test_deleted_directory
    skip "Cannot perform this test on windows" if win_platform?
    skip "Cannot perform this test on Solaris" if /solaris/ =~ RUBY_PLATFORM
    require "tmpdir"

    orig_dir = Dir.pwd

    begin
      Dir.mktmpdir("some_dir") do |dir|
        Dir.chdir(dir)
      end
    ensure
      Dir.chdir(orig_dir)
    end

    assert_nil bvf.bundler_version_with_reason
  end

  def test_compatible
    assert bvf.compatible?(util_spec("foo"))
    assert bvf.compatible?(util_spec("bundler", 1.1))

    bvf.stub(:bundler_version, v("1.1.1.1")) do
      assert bvf.compatible?(util_spec("foo"))
      assert bvf.compatible?(util_spec("bundler", "1.1.1.1"))
      assert bvf.compatible?(util_spec("bundler", "1.1.1.a"))
      assert bvf.compatible?(util_spec("bundler", "1.999"))
      refute bvf.compatible?(util_spec("bundler", "2.999"))
    end

    bvf.stub(:bundler_version, v("2.1.1.1")) do
      assert bvf.compatible?(util_spec("foo"))
      assert bvf.compatible?(util_spec("bundler", "2.1.1.1"))
      assert bvf.compatible?(util_spec("bundler", "2.1.1.a"))
      assert bvf.compatible?(util_spec("bundler", "2.999"))
      refute bvf.compatible?(util_spec("bundler", "1.999"))
      refute bvf.compatible?(util_spec("bundler", "3.0.0"))
    end
  end

  def test_filter
    versions = %w[1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3 3.a 3.0 3.1.1]
    specs = versions.map {|v| util_spec("bundler", v) }

    assert_equal %w[1 1.0 1.0.1.1 2 2.a 2.0 2.1.1 3 3.a 3.0 3.1.1], util_filter_specs(specs).map(&:version).map(&:to_s)

    bvf.stub(:bundler_version, v("2.1.1.1")) do
      assert_equal %w[2 2.a 2.0 2.1.1], util_filter_specs(specs).map(&:version).map(&:to_s)
    end
    bvf.stub(:bundler_version, v("1.1.1.1")) do
      assert_equal %w[1 1.0 1.0.1.1], util_filter_specs(specs).map(&:version).map(&:to_s)
    end
    bvf.stub(:bundler_version, v("1")) do
      assert_equal %w[1 1.0 1.0.1.1], util_filter_specs(specs).map(&:version).map(&:to_s)
    end
    bvf.stub(:bundler_version, v("2.a")) do
      assert_equal %w[2.a 2 2.0 2.1.1], util_filter_specs(specs).map(&:version).map(&:to_s)
    end
    bvf.stub(:bundler_version, v("3")) do
      assert_equal %w[3 3.a 3.0 3.1.1], util_filter_specs(specs).map(&:version).map(&:to_s)
    end
  end

  def util_filter_specs(specs)
    specs = specs.dup
    bvf.filter!(specs)
    specs
  end

end
