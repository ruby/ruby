
require 'benchmark'
require 'pp'

script = File.join(File.dirname(__FILE__), ARGV.shift)
script += '.rb' unless FileTest.exist?(script)
raise "#{script} not found" unless FileTest.exist?(script)

puts "Script: #{script}"

GC::Profiler.enable
tms = Benchmark.measure{|x|
  load script
}
gc_time = GC::Profiler.total_time
GC::Profiler.report if RUBY_VERSION >= '2.0.0' # before 1.9.3, report() may run infinite loop
GC::Profiler.disable
pp GC.stat

puts
puts script
puts Benchmark::CAPTION
puts tms
puts "GC total time (sec): #{gc_time}"
puts
puts "Summary #{RUBY_DESCRIPTION}\t#{tms.real}\t#{gc_time}\t#{GC.count}"
puts "         (real time in sec, GC time in sec, GC count)"
