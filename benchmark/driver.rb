#!/usr/bin/env ruby
#
# Ruby Benchmark driver
#

begin
  require 'optparse'
rescue LoadError
  $:.unshift File.join(File.dirname(__FILE__), '../lib')
  require 'optparse'
end

require 'shellwords'

class BenchmarkDriver
  # Run benchmark-driver prepared by `make update-benchmark-driver`
  def self.run(*args)
    benchmark_driver = File.expand_path('./benchmark-driver/exe/benchmark-driver', __dir__)
    command = [benchmark_driver, *args]
    unless system(command.shelljoin)
      abort "Failed to execute: #{command.shelljoin}"
    end
  end

  def initialize(opt = {})
    @dir = opt[:dir]
    @pattern = opt[:pattern]
    @exclude = opt[:exclude]
  end

  def files
    Dir.glob(File.join(@dir, '*.yml')).map{|file|
      next if @pattern && /#{@pattern}/ !~ File.basename(file)
      next if @exclude && /#{@exclude}/ =~ File.basename(file)
      file
    }.compact.sort
  end
end

if __FILE__ == $0
  opt = {
    execs: [],
    dir: File.dirname(__FILE__),
    repeat: 1,
    verbose: 1,
  }

  parser = OptionParser.new{|o|
    o.on('-e', '--executables [EXECS]',
      "Specify benchmark one or more targets (e1::path1; e2::path2; e3::path3;...)"){|e|
       e.split(/;/).each{|path|
         opt[:execs] << path
       }
    }
    o.on('--rbenv [VERSIONS]', 'Specify benchmark targets with rbenv version (vX.X.X;vX.X.X;...)'){|v|
      v.split(/;/).each{|version|
        opt[:execs] << "#{version}::#{`RBENV_VERSION='#{version}' rbenv which ruby`.rstrip}"
      }
    }
    o.on('-d', '--directory [DIRECTORY]', "Benchmark suites directory"){|d|
      opt[:dir] = d
    }
    o.on('-p', '--pattern [PATTERN]', "Benchmark name pattern"){|p|
      opt[:pattern] = p
    }
    o.on('-x', '--exclude [PATTERN]', "Benchmark exclude pattern"){|e|
      opt[:exclude] = e
    }
    o.on('-r', '--repeat-count [NUM]', "Repeat count"){|n|
      opt[:repeat] = n.to_i
    }
    o.on('-v', '--verbose'){|v|
      opt[:verbose] = 2
    }
    o.on('-q', '--quiet', "Run without notify information except result table."){|q|
      opt[:verbose] = 0
    }
  }

  parser.parse!(ARGV)

  execs = opt[:execs].map { |exec| ['--executables', exec.shellsplit.join(',')] }.flatten
  yamls = BenchmarkDriver.new(opt).files
  BenchmarkDriver.run(*yamls, *execs, "--verbose=#{opt[:verbose]}", "--repeat-count=#{opt[:repeat]}")
end
