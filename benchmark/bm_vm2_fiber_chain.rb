#!/usr/bin/env ruby

require 'benchmark'

def make_link(previous)
  Fiber.new do
    while message = previous.resume
      Fiber.yield(message)
    end
  end
end

def make_chain
  chain = Fiber.new do
    while true
      Fiber.yield(message)
    end
  end

  (fibers - 1).times do
    chain = make_link(chain)
  end

  return chain
end

def run_benchmark(fibers, repeats, message = :hello)
  chain = nil

  time = Benchmark.realtime do
    chain = make_chain
  end

  puts "Creating #{fibers} fibers took #{time}..."

  time = Benchmark.realtime do
    repeats.times do
      abort "invalid result" unless chain.resume == message
    end
  end

  puts "Passing #{repeats} messages took #{time}..."
end

n = (ARGV[0] || 1000).to_i
m = (ARGV[1] || 1000).to_i

5.times do
  run_benchmark(n, m)
end
