# frozen_string_literal: true
require 'rubygems/command'
require 'rubygems/commands/query_command'

##
# An alternate to Gem::Commands::QueryCommand that searches for gems starting
# with the supplied argument.

class Gem::Commands::ListCommand < Gem::Commands::QueryCommand

  def initialize
    super 'list', 'Display local gems whose name matches REGEXP'

    remove_option('--name-matches')
  end

  def arguments # :nodoc:
    "REGEXP        regexp to look for in gem name"
  end

  def defaults_str # :nodoc:
    "--local --no-details"
  end

  def description # :nodoc:
    <<-EOF
The list command is used to view the gems you have installed locally.

The --details option displays additional details including the summary, the
homepage, the author, the locations of different versions of the gem.

To search for remote gems use the search command.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [REGEXP ...]"
  end

end

