
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
puts "Summary (ruby): #{RUBY_DESCRIPTION} (#{script})"
puts "Summary (real): #{tms.real} sec"
puts "Summary (gctm): #{gc_time} sec"
puts "Summary (gc#) : #{GC.count}"
