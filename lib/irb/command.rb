# frozen_string_literal: true
#
#   irb/command.rb - irb command
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative "command/base"

module IRB # :nodoc:
  module Command
    @commands = {}

    class << self
      attr_reader :commands

      # Registers a command with the given name.
      # Aliasing is intentionally not supported at the moment.
      def register(name, command_class)
        @commands[name] = [command_class, []]
      end

      # This API is for IRB's internal use only and may change at any time.
      # Please do NOT use it.
      def _register_with_aliases(name, command_class, *aliases)
        @commands[name] = [command_class, aliases]
      end
    end
  end
end
