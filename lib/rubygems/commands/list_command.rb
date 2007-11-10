require 'rubygems/command'
require 'rubygems/commands/query_command'

module Gem
  module Commands
    class ListCommand < QueryCommand

      def initialize
        super(
          'list',
          'Display all gems whose name starts with STRING'
        )
        remove_option('--name-matches')
      end

      def arguments # :nodoc:
        "STRING        start of gem name to look for"
      end

      def defaults_str # :nodoc:
        "--local --no-details"
      end

      def usage # :nodoc:
        "#{program_name} [STRING]"
      end

      def execute
        string = get_one_optional_argument || ''
        options[:name] = /^#{string}/i
        super
      end
    end
  end
end
