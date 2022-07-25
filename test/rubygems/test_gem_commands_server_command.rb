# frozen_string_literal: true
require_relative "helper"
require "rubygems/commands/server_command"

class TestGemCommandsServerCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::ServerCommand.new
  end

  def test_execute
    use_ui @ui do
      @cmd.execute
    end

    assert_match %r{Install the rubygems-server}i, @ui.error
  end
end
