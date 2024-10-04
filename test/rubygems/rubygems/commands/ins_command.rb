# frozen_string_literal: true

class Gem::Commands::InsCommand < Gem::Command
  def initialize
    super("ins", "Does something different from install", {})
  end
end
