require 'rubygems/command'
require 'rubygems/commands/list_command'

class Gem::Commands::SearchCommand < Gem::Commands::ListCommand

  def initialize
    super 'search', 'Display all gems whose name contains STRING'

    @defaults[:domain] = :remote
  end

  def defaults_str # :nodoc:
    "--remote --no-details"
  end

end

