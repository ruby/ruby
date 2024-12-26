# frozen_string_literal: true

# This is a simple debugging helper method that can be used to
# print out the source file and line number of the caller
# together with the debugged value.

# Usage:
# dbg("Hello world", [1, 2, 3])
# => [file.rb:12] "Hello world"
# => [file.rb:12] [1, 2, 3]

def dbg(*msgs)
  loc = caller_locations.first.to_s
  matching_loc = loc.match(/.+(rb)\:\d+\:(in)\s/)
  src = if matching_loc.nil?
      loc
    else
      matching_loc[0][0..-5]
    end
  file, line = src.split(":")
  file = file.split("/").last(2).join("/")
  src = "[#{file}:#{line}]"

  msgs.each do |msg|
    puts "#{src} #{msg.inspect}"
  end
  nil
end
