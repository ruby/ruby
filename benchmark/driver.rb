#!/usr/bin/env ruby
#
# Wrapper of benchmark-driver command for `make benchmark` and `make benchmark-each`.
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
    runner: 'ips',
    output: 'compare',
    execs: [],
    rbenvs: [],
    repeat: 1,
    verbose: [],
    dir: File.dirname(__FILE__),
  }

  parser = OptionParser.new{|o|
    #
    # Original benchmark-driver imitation
    #
    o.on('-r', '--runner [TYPE]', 'Specify runner type: ips, time, memory, once (default: ips)'){|r|
      abort '-r, --runner must take argument but not given' if r.nil?
      opt[:runner] = r
    }
    o.on('-o', '--output [TYPE]', 'Specify output type: compare, simple, markdown, record (default: compare)'){|o|
      abort '-o, --output must take argument but not given' if o.nil?
      opt[:output] = o
    }
    o.on('-e', '--executables [EXECS]',
      "Specify benchmark one or more targets (e1::path1; e2::path2; e3::path3;...)"){|e|
       e.split(/;/).each{|path|
         opt[:execs] << path
       }
    }
    o.on('--rbenv [VERSIONS]', 'Specify benchmark targets with rbenv version (vX.X.X;vX.X.X;...)'){|v|
      opt[:rbenvs] << v
    }
    o.on('--repeat-count [NUM]', "Repeat count"){|n|
      opt[:repeat] = n.to_i
    }
    o.on('-v', '--verbose', 'Verbose mode. Multiple -v options increase visilibity (max: 2)'){|v|
      opt[:verbose] << '-v'
    }

    #
    # benchmark/driver.rb original (deprecated, to be removed later)
    #
    o.on('--directory [DIRECTORY]', "Benchmark suites directory"){|d|
      opt[:dir] = d
    }
    o.on('--pattern [PATTERN]', "Benchmark name pattern"){|p|
      opt[:pattern] = p
    }
    o.on('--exclude [PATTERN]', "Benchmark exclude pattern"){|e|
      opt[:exclude] = e
    }
  }

  yamls = parser.parse!(ARGV)
  yamls += BenchmarkDriver.new(opt).files

  # Many variables in Makefile are not `foo,bar` but `foo bar`. So it's converted here.
  execs = opt[:execs].map { |exec| ['--executables', exec] }.flatten
  rbenv = opt[:rbenvs].map { |r| ['--rbenv', r] }

  BenchmarkDriver.run(
    *yamls, *execs, *rbenv, *opt[:verbose],
    "--runner=#{opt[:runner]}", "--output=#{opt[:output]}",
    "--repeat-count=#{opt[:repeat]}",
  )
end
