#!/usr/bin/env ruby

module Rake

  # Makefile loader to be used with the import file loader.
  class MakefileLoader

    # Load the makefile dependencies in +fn+.
    def load(fn)
      buffer = ''
      open(fn) do |mf|
        mf.each do |line|
          next if line =~ /^\s*#/
          buffer << line
          if buffer =~ /\\$/
            buffer.sub!(/\\\n/, ' ')
            state = :append
          else
            process_line(buffer)
            buffer = ''
          end
        end
      end
      process_line(buffer) if buffer != ''
    end

    private

    # Process one logical line of makefile data.
    def process_line(line)
      file_task, args = line.split(':')
      return if args.nil?
      dependents = args.split
      file file_task => dependents
    end
  end

  # Install the handler
  Rake.application.add_loader('mf', MakefileLoader.new)
end
