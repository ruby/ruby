
require 'rdoc/rdoc'
require 'tmpdir'
require 'benchmark'
require 'pp'

Dir.mktmpdir('rdocbench-'){|d|
  dir = File.join(d, 'rdocbench')
  args = ARGV.dup
  args << '--op' << dir

  GC::Profiler.enable
  tms = Benchmark.measure{|x|
    r = RDoc::RDoc.new
    r.document args
  }
  GC::Profiler.report
  pp GC.stat
  puts
  puts Benchmark::CAPTION
  puts tms
  puts "GC total time (sec): #{GC::Profiler.total_time}"
  puts
  puts "Summary (ruby): #{RUBY_DESCRIPTION})"
  puts "Summary (real): #{tms.real} sec"
  puts "Summary (gctm): #{GC::Profiler.total_time} sec"
  puts "Summary (gc#) : #{GC.count}"
}
