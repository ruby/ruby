# frozen_string_literal: true

require_relative "../source_finder"
require_relative "../pager"
require_relative "../color"

module IRB
  module Command
    class ShowSource < Base
      category "Context"
      description "Show the source code of a given method, class/module, or constant."

      help_message <<~HELP_MESSAGE
        Usage: show_source [target] [-s]

          -s  Show the super method. You can stack it like `-ss` to show the super of the super, etc.

        Examples:

          show_source Foo
          show_source Foo#bar
          show_source Foo#bar -s
          show_source Foo.baz
          show_source Foo::BAR
      HELP_MESSAGE

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

        str, esses = str.split(" -")
        super_level = esses ? esses.count("s") : 0
        source = SourceFinder.new(@irb_context).find_source(str, super_level)

        if source
          show_source(source)
        elsif super_level > 0
          puts "Error: Couldn't locate a super definition for #{str}"
        else
          puts "Error: Couldn't locate a definition for #{str}"
        end
        nil
      end

      private

      def show_source(source)
        if source.binary_file?
          content = "\n#{bold('Defined in binary file')}: #{source.file}\n\n"
        else
          code = source.colorized_content || 'Source not available'
          content = <<~CONTENT

            #{bold("From")}: #{source.file}:#{source.line}

            #{code.chomp}

          CONTENT
        end
        Pager.page_content(content)
      end

      def bold(str)
        Color.colorize(str, [:BOLD])
      end
    end
  end
end
