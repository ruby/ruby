# frozen_string_literal: true

require_relative "nop"
require_relative "../source_finder"
require_relative "../color"

module IRB
  module ExtendCommand
    class ShowSource < Nop
      category "Context"
      description "Show the source code of a given method or constant."

      class << self
        def transform_args(args)
          # Return a string literal as is for backward compatibility
          if args.empty? || string_literal?(args)
            args
          else # Otherwise, consider the input as a String for convenience
            args.strip.dump
          end
        end
      end

      def execute(str = nil)
        unless str.is_a?(String)
          puts "Error: Expected a string but got #{str.inspect}"
          return
        end

        source = SourceFinder.new(@irb_context).find_source(str)

        if source
          show_source(source)
        else
          puts "Error: Couldn't locate a definition for #{str}"
        end
        nil
      end

      private

      def show_source(source)
        puts
        puts "#{bold("From")}: #{source.file}:#{source.first_line}"
        puts
        code = IRB::Color.colorize_code(File.read(source.file))
        puts code.lines[(source.first_line - 1)...source.last_line].join
        puts
      end

      def bold(str)
        Color.colorize(str, [:BOLD])
      end
    end
  end
end
