# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/list_command'

class TestGemCommandsListCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::ListCommand.new

    spec_fetcher do |fetcher|
      fetcher.spec 'c', 1
    end

    @fetcher.data["#{@gem_repo}Marshal.#{Gem.marshal_version}"] = proc do
      raise Gem::RemoteFetcher::FetchError
    end
  end

  def test_execute_installed
    @cmd.handle_options %w[c --installed]

    assert_raises Gem::MockGemUi::SystemExitException do
      use_ui @ui do
        @cmd.execute
      end
    end

    assert_equal "true\n", @ui.output
    assert_equal '', @ui.error
  end

end
