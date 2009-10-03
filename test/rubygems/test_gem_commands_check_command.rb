#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

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
