require 'rubygems/command_manager'

class Gem::Commands::InterruptCommand < Gem::Command

  def initialize
    super('interrupt', 'Raises an Interrupt Exception', {})
  end

  def execute
    raise Interrupt, "Interrupt exception"
  end

end

Gem::CommandManager.instance.register_command :interrupt

