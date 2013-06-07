
require 'rdoc/rdoc'
require 'tmpdir'
require 'benchmark'
require 'pp'

Dir.mktmpdir('rdocbench-'){|d|
  dir = File.join(d, 'rdocbench')
  args = ARGV.dup
  args << '--op' << dir

  GC::Profiler.enable
  Benchmark.bm{|x|
    x.report('rdoc'){
      r = RDoc::RDoc.new
      r.document args
      GC::Profiler.report
      pp GC.stat
      puts "GC Total Time:#{GC::Profiler.total_time}"
    }
  }
}
