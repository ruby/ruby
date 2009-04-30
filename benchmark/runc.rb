#
#
#

require 'benchmark'
require 'rbconfig'

$rubybin = ENV['RUBY'] || File.join(
  RbConfig::CONFIG["bindir"],
  RbConfig::CONFIG["ruby_install_name"] + RbConfig::CONFIG["EXEEXT"])

def runfile file
  puts file
  file = File.join(File.dirname($0), 'contrib', file)
  Benchmark.bm{|x|
    x.report('ruby'){
      system("#{$rubybin} #{file}")
    }
    x.report('yarv'){
      system("#{$rubybin} -rite -I.. #{file}")
    }
  }
end

ARGV.each{|file|
  runfile file
}


