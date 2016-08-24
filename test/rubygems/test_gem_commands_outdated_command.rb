# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/outdated_command'

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
      fetcher.download 'foo', '1.0'
      fetcher.download 'foo', '2.0'
      fetcher.gem 'foo', '0.1'
      fetcher.gem 'foo', '0.2'
    end

    use_ui @ui do
      @cmd.execute
    end

    assert_equal "foo (0.2 < 2.0)\n", @ui.output
    assert_equal "", @ui.error
  end
end

