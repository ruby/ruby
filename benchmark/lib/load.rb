# How to use this file:
#   1. write a `$(srcdir)/test.rb` like:
=begin
require_relative 'benchmark/lib/load'

Benchmark.driver(repeat_count: 5){|x|
  x.executable name: 'clean-miniruby', command: %w'../clean-trunk/miniruby'
  x.executable name: 'modif-miniruby', command: %w'./miniruby'

  x.report %q{
    h = {a: 1, b: 2, c: 3, d: 4}
  }
}
=end
#
#  2. `make run`
$:.unshift(File.join(__dir__, '../benchmark-driver/lib'))
require 'benchmark_driver'
