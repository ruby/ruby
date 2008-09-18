#!/usr/bin/env ruby

module Rake

  # Makefile loader to be used with the import file loader.
  class MakefileLoader

    # Load the makefile dependencies in +fn+.
    def load(fn)
      open(fn) do |mf|
        lines = mf.read
        lines.gsub!(/#[^\n]*\n/m, "")
        lines.gsub!(/\\\n/, ' ')
        lines.split("\n").each do |line|
          process_line(line)
        end
      end
    end

    private

    # Process one logical line of makefile data.
    def process_line(line)
      file_tasks, args = line.split(':')
      return if args.nil?
      dependents = args.split
      file_tasks.strip.split.each do |file_task|
        file file_task => dependents
      end
    end
  end

  # Install the handler
  Rake.application.add_loader('mf', MakefileLoader.new)
end
