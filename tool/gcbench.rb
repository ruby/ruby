
require 'benchmark'
require 'pp'

script = ARGV.shift || raise

GC::Profiler.enable
tms = Benchmark.measure{|x|
  load script
}
GC::Profiler.report
pp GC.stat

gc_time = GC::Profiler.total_time

puts
puts Benchmark::CAPTION
puts tms
puts "GC total time (sec): #{gc_time}"
puts
puts "Summary #{RUBY_DESCRIPTION}\t#{tms.real}\t#{gc_time}\t#{GC.count}"
puts "         (real time in sec, GC time in sec, GC count)"
