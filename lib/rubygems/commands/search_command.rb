require 'rubygems/command'
require 'rubygems/commands/query_command'

class Gem::Commands::SearchCommand < Gem::Commands::QueryCommand

  def initialize
    super 'search', 'Display remote gems whose name contains STRING'

    remove_option '--name-matches'

    defaults[:domain] = :remote
  end

  def arguments # :nodoc:
    "STRING        fragment of gem name to search for"
  end

  def defaults_str # :nodoc:
    "--remote --no-details"
  end

  def description # :nodoc:
    <<-EOF
The search command displays remote gems whose name contains the given
string.

The --details option displays additional details from the gem but will
take a little longer to complete as it must download the information
individually from the index.

To list local gems use the list command.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} [STRING]"
  end

end

