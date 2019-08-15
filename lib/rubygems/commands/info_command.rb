# frozen_string_literal: true

require 'rubygems/command'
require 'rubygems/commands/query_command'

class Gem::Commands::InfoCommand < Gem::Commands::QueryCommand

  def initialize
    super "info", "Show information for the given gem"

    remove_option('--name-matches')
    remove_option('-d')

    defaults[:details] = true
    defaults[:exact] = true
  end

  def description # :nodoc:
    "Info prints information about the gem such as name,"\
    " description, website, license and installed paths"
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME"
  end

  def arguments # :nodoc:
    "GEMNAME        name of the gem to print information about"
  end

  def defaults_str
    "--local"
  end

end
