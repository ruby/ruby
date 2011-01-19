######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "test/rubygems/gemutilities"
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
