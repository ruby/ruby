require 'shellwords'

require_relative "../source_finder"

module IRB
  # :stopdoc:

  module Command
    class Edit < Base
      category "Misc"
      description 'Open a file with the editor command defined with `ENV["VISUAL"]` or `ENV["EDITOR"]`.'

      class << self
        def transform_args(args)
          # Return a string literal as is for backward compatibility
          if args.nil? || args.empty? || string_literal?(args)
            args
          else # Otherwise, consider the input as a String for convenience
            args.strip.dump
          end
        end
      end

      def execute(*args)
        path = args.first

        if path.nil?
          path = @irb_context.irb_path
        elsif !File.exist?(path)
          source = SourceFinder.new(@irb_context).find_source(path)

          if source&.file_exist? && !source.binary_file?
            path = source.file
          end
        end

        unless File.exist?(path)
          puts "Can not find file: #{path}"
          return
        end

        if editor = (ENV['VISUAL'] || ENV['EDITOR'])
          puts "command: '#{editor}'"
          puts "   path: #{path}"
          system(*Shellwords.split(editor), path)
        else
          puts "Can not find editor setting: ENV['VISUAL'] or ENV['EDITOR']"
        end
      end
    end
  end

  # :startdoc:
end
