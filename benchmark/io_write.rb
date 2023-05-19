#!/usr/bin/env ruby

require 'benchmark'

SIZE = 128
ARGUMENTS = 100
REPEATS = 10000

output = File.open(File::NULL, "w")
output.sync = true

DOT = ("." * SIZE).freeze
chunks = ARGUMENTS.times.collect{DOT}

REPEATS.times do
  # output.write(*chunks)
  output.puts(*chunks)
end

output.close
