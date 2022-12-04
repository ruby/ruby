#!/usr/bin/env ruby

require 'benchmark'

i, o = IO.pipe
o.sync = true

DOT = ".".freeze

chunks = 100_000.times.collect{DOT}

thread = Thread.new do
  while i.read(1024)
  end
end

100.times do
  o.write(*chunks)
end

o.close
thread.join
