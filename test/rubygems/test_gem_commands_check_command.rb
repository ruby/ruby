require_relative 'gemutilities'
require 'rubygems/commands/check_command'

class TestGemCommandsCheckCommand < RubyGemTestCase

  def setup
    super

    @cmd = Gem::Commands::CheckCommand.new
  end

  def test_initialize
    assert_equal "check", @cmd.command
    assert_equal "gem check", @cmd.program_name
    assert_match(/Check/, @cmd.summary)
  end

end
