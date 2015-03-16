require 'benchmark'
require 'pp'
require 'optparse'

$list = true
$gcprof = true

opt = OptionParser.new
opt.on('-q'){$list = false}
opt.on('-d'){$gcprof = false}
opt.parse!(ARGV)

script = File.join(File.dirname(__FILE__), ARGV.shift)
script += '.rb' unless FileTest.exist?(script)
raise "#{script} not found" unless FileTest.exist?(script)

puts "Script: #{script}"

if $gcprof
  GC::Profiler.enable
end

tms = Benchmark.measure{|x|
  load script
}

gc_time = 0

if $gcprof
  gc_time = GC::Profiler.total_time
  GC::Profiler.report if $list and RUBY_VERSION >= '2.0.0' # before 1.9.3, report() may run infinite loop
  GC::Profiler.disable
end

pp GC.stat

puts "#{RUBY_DESCRIPTION} #{GC::OPTS.inspect}" if defined?(GC::OPTS)

desc = "#{RUBY_VERSION}#{RUBY_PATCHLEVEL >= 0 ? "p#{RUBY_PATCHLEVEL}" : "dev"}"
name = File.basename(script, '.rb')

puts
puts script
puts Benchmark::CAPTION
puts tms
puts "GC total time (sec): #{gc_time}"

# show High-Water Mark on Linux
if File.exist?('/proc/self/status') && /VmHWM:\s*(\d+.+)/ =~ File.read('/proc/self/status')
  puts
  puts "VmHWM: #{$1.chomp}"
end

puts
puts "Summary of #{name} on #{desc}\t#{tms.real}\t#{gc_time}\t#{GC.count}"
puts "         (real time in sec, GC time in sec, GC count)"
