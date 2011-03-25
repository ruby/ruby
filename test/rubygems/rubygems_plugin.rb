######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/command_manager'

##
# This is an example of exactly what NOT to do.
#
# DO NOT include code like this in your rubygems_plugin.rb

class Gem::Commands::InterruptCommand < Gem::Command

  def initialize
    super('interrupt', 'Raises an Interrupt Exception', {})
  end

  def execute
    raise Interrupt, "Interrupt exception"
  end

end

Gem::CommandManager.instance.register_command :interrupt

