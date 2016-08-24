# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/search_command'

class TestGemCommandsSearchCommand < Gem::TestCase

  def setup
    super

    @cmd = Gem::Commands::SearchCommand.new
  end

  def test_initialize
    assert_equal :remote, @cmd.defaults[:domain]
  end

end

