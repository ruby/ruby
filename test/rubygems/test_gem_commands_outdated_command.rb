# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/outdated_command"

class TestGemCommandsOutdatedCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::OutdatedCommand.new
  end

  def test_initialize
    assert @cmd.handles?(%W[--platform #{Gem::Platform.local}])
  end

  def test_execute
    spec_fetcher do |fetcher|
      fetcher.download "foo", "1.0"
      fetcher.download "foo", "2.0"
      fetcher.gem "foo", "0.1"
      fetcher.gem "foo", "0.2"
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo (0.2 < 2.0)\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_compact_index
    spec_fetcher do |fetcher|
      fetcher.gem "foo", "0.2"
    end

    foo2 = util_spec "foo", "2.0"
    util_setup_compact_index foo2

    # drop the in-memory tuples spec_fetcher pre-populated so the lookup
    # goes through Gem::Source#load_specs
    Gem::SpecFetcher.fetcher = nil

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo (0.2 < 2.0)\n", @ui.output
    assert_equal "", @ui.error
  end

  def util_cooldown_time(days_ago)
    (Time.now - days_ago * 86_400).utc.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  def util_setup_cooldown_repo(created_at)
    spec_fetcher do |fetcher|
      fetcher.gem "foo", "0.1"
    end

    specs = created_at.keys.map {|full_name| util_spec "foo", full_name.delete_prefix("foo-") }
    util_setup_compact_index(*specs, created_at: created_at.compact)

    # drop the in-memory tuples spec_fetcher pre-populated so the lookup
    # goes through Gem::Source#load_specs
    Gem::SpecFetcher.fetcher = nil
  end

  def test_execute_cooldown_annotates_newer_version_within_period
    util_setup_cooldown_repo "foo-0.2" => util_cooldown_time(30),
                             "foo-0.3" => util_cooldown_time(1)

    @cmd.options[:cooldown] = 7

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo (0.1 < 0.2, 0.3 (cooldown 7d))\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_cooldown_only_version_within_period
    util_setup_cooldown_repo "foo-0.3" => util_cooldown_time(1)

    @cmd.options[:cooldown] = 7

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo (0.1 < 0.3 (cooldown 7d))\n", @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_cooldown_missing_created_at_fails_open
    util_setup_cooldown_repo "foo-0.2" => nil, "foo-0.3" => nil

    @cmd.options[:cooldown] = 7

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo (0.1 < 0.3)\n", @ui.output
    assert_equal 1, @ui.error.scan("publish times").size
  end

  def test_cooldown_option
    @cmd.handle_options %w[--cooldown 7]

    assert_equal 7, @cmd.options[:cooldown]
  end

  def test_execute_with_up_to_date_platform_specific_gem
    spec_fetcher do |fetcher|
      fetcher.download "foo", "2.0"

      fetcher.gem "foo", "1.0"
      fetcher.gem "foo", "2.0" do |s|
        s.platform = Gem::Platform.local
      end
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "", @ui.output
    assert_equal "", @ui.error
  end
end
