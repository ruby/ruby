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
