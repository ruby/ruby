######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require 'rubygems/command'
require 'rubygems/commands/query_command'

class Gem::Commands::SearchCommand < Gem::Commands::QueryCommand

  def initialize
    super 'search', 'Display all gems whose name contains STRING'

    remove_option '--name-matches'
  end

  def arguments # :nodoc:
    "STRING        fragment of gem name to search for"
  end

  def defaults_str # :nodoc:
    "--local --no-details"
  end

  def usage # :nodoc:
    "#{program_name} [STRING]"
  end

  def execute
    string = get_one_optional_argument
    options[:name] = /#{string}/i
    super
  end

end

