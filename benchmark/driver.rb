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
require 'tempfile'

class BenchmarkDriver
  # Run benchmark-driver prepared by `make update-benchmark-driver`
  def self.run(*args)
    benchmark_driver = File.expand_path('./benchmark-driver/exe/benchmark-driver', __dir__)
    command = [benchmark_driver, *args]
    unless system(command.shelljoin)
      abort "Failed to execute: #{command.shelljoin}"
    end
  end

  def initialize(dir, opt = {})
    @dir = dir
    @pattern = opt[:pattern] || nil
    @exclude = opt[:exclude] || nil
  end

  def with_yamls(&block)
    ios = files.map do |file|
      Tempfile.open.tap do |io|
        if file.end_with?('.yml')
          io.write(File.read(file))
        else
          io.write(build_yaml(file))
        end
        io.close
      end
    end
    block.call(ios.map(&:path))
  ensure
    ios.each(&:close)
  end

  private

  def build_yaml(file)
    magic_comment = '# prelude' # bm_so_nsieve_bits hangs without magic comment
    name = File.basename(file).sub(/\Abm_/, '').sub(/\.rb\z/, '')
    script = File.read(file).sub(/^__END__\n(.+\n)*/m, '').sub(/\A(^#[^\n]+\n)+/m) do |comment|
      magic_comment = comment
      ''
    end

    <<-YAML
prelude: |
#{magic_comment.gsub(/^/, '  ')}
benchmark:
  #{name}: |
#{script.gsub(/^/, '    ')}
loop_count: 1
    YAML
  end

  def files
    flag = {}
    legacy_files = Dir.glob(File.join(@dir, 'bm*.rb'))
    yaml_files = Dir.glob(File.join(@dir, '*.yml'))
    files = (legacy_files + yaml_files).map{|file|
      next if @pattern && /#{@pattern}/ !~ File.basename(file)
      next if @exclude && /#{@exclude}/ =~ File.basename(file)
      case file
      when /bm_(vm2)_/, /bm_loop_(whileloop2).rb/
        flag[$1] = true
      end
      file
    }.compact

    if flag['vm2'] && !flag['whileloop2']
      files << File.join(@dir, 'bm_loop_whileloop2.rb')
    end

    files.sort!
    files
  end
end

if __FILE__ == $0
  opt = {
    :execs => [],
    :dir => File.dirname(__FILE__),
    :repeat => 1,
    :verbose => 1,
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
  BenchmarkDriver.new(opt[:dir], opt).with_yamls do |yamls|
    BenchmarkDriver.run(*yamls, *execs, "--verbose=#{opt[:verbose]}", "--repeat-count=#{opt[:repeat]}")
  end
end
