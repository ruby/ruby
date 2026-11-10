# frozen_string_literal: true

require_relative "helper"
require "rubygems/bundler_settings"

class TestGemBundlerSettings < Gem::TestCase
  def setup
    super

    @gemfile = File.join @tempdir, "Gemfile"
    FileUtils.touch @gemfile
    ENV["BUNDLE_GEMFILE"] = @gemfile
  end

  def test_reads_the_environment_variable
    ENV["BUNDLE_COOLDOWN"] = "7"

    assert_equal "7", Gem::BundlerSettings["cooldown"]
  end

  def test_ignores_an_empty_environment_variable
    ENV["BUNDLE_COOLDOWN"] = ""

    assert_nil Gem::BundlerSettings["cooldown"]
  end

  def test_reads_the_user_config_file
    write_global_config "BUNDLE_COOLDOWN: \"7\"\n"

    assert_equal "7", Gem::BundlerSettings["cooldown"]
  end

  def test_reads_the_application_config_file
    write_app_config "BUNDLE_COOLDOWN: \"7\"\n"

    assert_equal "7", Gem::BundlerSettings["cooldown"]
  end

  def test_application_config_file_wins_over_the_environment_and_the_user_file
    write_app_config "BUNDLE_COOLDOWN: \"3\"\n"
    ENV["BUNDLE_COOLDOWN"] = "5"
    write_global_config "BUNDLE_COOLDOWN: \"7\"\n"

    assert_equal "3", Gem::BundlerSettings["cooldown"]
  end

  def test_environment_wins_over_the_user_config_file
    ENV["BUNDLE_COOLDOWN"] = "5"
    write_global_config "BUNDLE_COOLDOWN: \"7\"\n"

    assert_equal "5", Gem::BundlerSettings["cooldown"]
  end

  def test_bundle_app_config_relocates_the_application_config_file
    dir = File.join @tempdir, "elsewhere"
    FileUtils.mkdir_p dir
    File.write File.join(dir, "config"), "BUNDLE_COOLDOWN: \"7\"\n"

    write_app_config "BUNDLE_COOLDOWN: \"3\"\n"
    ENV["BUNDLE_APP_CONFIG"] = dir

    assert_equal "7", Gem::BundlerSettings["cooldown"]
  end

  def test_relative_bundle_app_config_resolves_against_the_gemfile
    dir = File.join @tempdir, "elsewhere"
    FileUtils.mkdir_p dir
    File.write File.join(dir, "config"), "BUNDLE_COOLDOWN: \"7\"\n"

    ENV["BUNDLE_APP_CONFIG"] = "elsewhere"

    assert_equal "7", Gem::BundlerSettings["cooldown"]
  end

  def test_bundle_user_home_joins_the_config_file_name
    dir = File.join @tempdir, "user_home"
    FileUtils.mkdir_p dir
    File.write File.join(dir, "config"), "BUNDLE_COOLDOWN: \"7\"\n"

    ENV["BUNDLE_USER_HOME"] = dir

    assert_equal "7", Gem::BundlerSettings["cooldown"]
  end

  def test_falls_back_to_the_dot_bundle_directory_in_the_home_directory
    dir = File.join @userhome, ".bundle"
    FileUtils.mkdir_p dir
    File.write File.join(dir, "config"), "BUNDLE_COOLDOWN: \"7\"\n"

    assert_equal "7", Gem::BundlerSettings["cooldown"]
  end

  def test_bundle_ignore_config_drops_the_config_files
    write_app_config "BUNDLE_COOLDOWN: \"3\"\n"
    write_global_config "BUNDLE_COOLDOWN: \"7\"\n"
    ENV["BUNDLE_IGNORE_CONFIG"] = "1"

    assert_nil Gem::BundlerSettings["cooldown"]

    ENV["BUNDLE_COOLDOWN"] = "5"

    assert_equal "5", Gem::BundlerSettings["cooldown"]
  end

  def test_unset_key_is_nil
    write_global_config "BUNDLE_JOBS: \"8\"\n"

    assert_nil Gem::BundlerSettings["cooldown"]
  end

  def test_from_config_files_skips_the_environment
    ENV["BUNDLE_COOLDOWN"] = "5"
    write_global_config "BUNDLE_COOLDOWN: \"7\"\n"

    assert_equal "7", Gem::BundlerSettings.from_config_files("cooldown")
  end

  def test_env_reads_only_the_environment
    write_global_config "BUNDLE_COOLDOWN: \"7\"\n"

    assert_nil Gem::BundlerSettings.env("cooldown")

    ENV["BUNDLE_COOLDOWN"] = "5"

    assert_equal "5", Gem::BundlerSettings.env("cooldown")
  end

  def test_dotted_and_dashed_names_take_the_key_bundler_writes
    write_global_config "BUNDLE_GEM__TEST: \"minitest\"\n"

    assert_equal "minitest", Gem::BundlerSettings["gem.test"]
  end

  def test_unreadable_config_file_is_ignored
    ENV["BUNDLE_CONFIG"] = File.join @tempdir, "no", "such", "config"

    assert_nil Gem::BundlerSettings["cooldown"]
  end

  def test_config_file_without_a_mapping_is_ignored
    ["- one\n- two\n", "BUNDLE_COOLDOWN:7\n"].each do |contents|
      write_global_config contents

      assert_nil Gem::BundlerSettings["cooldown"], contents
    end
  end

  def test_unparsable_config_file_is_ignored
    ["BUNDLE_COOLDOWN: !ruby/object:Foo {}\n", "BUNDLE_COOLDOWN: *nowhere\n"].each do |contents|
      write_global_config contents

      assert_nil Gem::BundlerSettings["cooldown"], contents
    end
  end

  def test_gemfile_path_from_the_environment
    assert_equal @gemfile, Gem::BundlerSettings.gemfile_path
  end

  def test_gemfile_path_found_by_walking_up
    ENV["BUNDLE_GEMFILE"] = nil
    nested = File.join @tempdir, "a", "b"
    FileUtils.mkdir_p nested

    Dir.chdir nested do
      assert_equal @gemfile, Gem::BundlerSettings.gemfile_path
    end
  end

  def test_gemfile_path_without_a_gemfile
    ENV["BUNDLE_GEMFILE"] = nil
    File.delete @gemfile

    Dir.chdir @tempdir do
      assert_nil Gem::BundlerSettings.gemfile_path
    end
  end

  def write_app_config(contents)
    dir = File.join @tempdir, ".bundle"
    FileUtils.mkdir_p dir
    File.write File.join(dir, "config"), contents
  end

  def write_global_config(contents)
    path = File.join @tempdir, "global_config"
    File.write path, contents
    ENV["BUNDLE_CONFIG"] = path
  end
end
