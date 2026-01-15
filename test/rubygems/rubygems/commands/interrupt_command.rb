# frozen_string_literal: true

class Gem::Commands::InterruptCommand < Gem::Command
  def initialize
    super("interrupt", "Raises an Interrupt Exception", {})
  end

  def execute
    raise Interrupt, "Interrupt exception"
  end
end
