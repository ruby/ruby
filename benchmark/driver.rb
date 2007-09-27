#
# Ruby Benchmark driver
#

require 'optparse'
require 'benchmark'
require 'pp'

class BenchmarkDriver
  def self.benchmark(opt)
    driver = self.new(opt[:execs], opt[:dir], opt)
    begin
      driver.run
    ensure
      driver.show_results
    end
  end

  def initialize execs, dir, opt = {}
    @execs = execs.map{|e|
      e.strip!
      next if e.empty?

      v =  `#{e} -v`.chomp
      v.sub!(' patchlevel 0', '')
      [e, v]
    }.compact

    @dir = dir
    @repeat = opt[:repeat] || 1
    @repeat = 1 if @repeat < 1
    @pattern = opt[:pattern] || nil
    @verbose = opt[:quiet] ? false : (opt[:verbose] || false)
    @loop_wl1 = @loop_wl2 = nil
    @opt = opt

    # [[name, [[r-1-1, r-1-2, ...], [r-2-1, r-2-2, ...]]], ...]
    @results = []

    if @verbose
      puts Time.now
      @execs.each_with_index{|(e, v), i|
        puts "target #{i}: #{v}"
      }
    end
  end

  def show_results
    if @verbose
      puts '-----------------------------------------------------------'
      puts 'raw data:'
      pp @results
    end

    puts '-----------------------------------------------------------'
    puts 'benchmark results:'
    if @verbose and @repeat > 1
      puts "minimum results in each #{@repeat} measurements."
    end
    puts "name\t#{@execs.map{|(e, v)| v}.join("\t")}"
    @results.each{|v, result|
      rets = []
      s = nil
      result.each_with_index{|e, i|
        r = e.min
        case v
        when /^vm1_/
          if @loop_wl1
            r -= @loop_wl1[i]
            s = '*'
          end
        when /^vm2_/
          if @loop_wl2
            r -= @loop_wl2[i]
            s = '*'
          end
        end
        rets << sprintf("%.3f", r)
      }
      puts "#{v}#{s}\t#{rets.join("\t")}"
    }

  end

  def run
    Dir.glob(File.join(@dir, 'bm*.rb')){|file|
      next if @pattern && /#{@pattern}/ !~ File.basename(file)

      if /bm_vm1_/ =~ file and !@loop_wl1
        r = measure_file(File.join(File.dirname(file), 'bm_loop_whileloop.rb'))
        @loop_wl1 = r[1].map{|e| e.min}
      elsif /bm_vm1_/ =~ file and !@loop_wl2
        r = measure_file(File.join(File.dirname(file), 'bm_loop_whileloop2.rb'))
        @loop_wl2 = r[1].map{|e| e.min}
      end

      measure_file(file)
    }
  end

  def measure_file file
    name = File.basename(file, '.rb').sub(/^bm_/, '')
    prepare_file = File.join(File.dirname(file), "prepare_#{name}.rb")
    load prepare_file if FileTest.exist?(prepare_file)

    if @verbose
      puts '-----------------------------------------------------------'
      puts name
      puts File.read(file)
      puts
    end

    result = [name]
    result << @execs.map{|(e, v)|
      (0...@repeat).map{
        print "#{v}\t" if @verbose
        STDOUT.flush
        m = measure e, file
        puts "#{m}" if @verbose
        m
      }
    }
    @results << result
    result
  end

  def measure executable, file
    m = Benchmark.measure{
      `#{executable} #{file}`
    }

    if $? != 0
      raise "Benchmark process exited with abnormal status (#{$?})"
    end
    m.real
  end
end

if __FILE__ == $0
  opt = {
    :execs => ['ruby'],
    :dir => './',
    :repeat => 1,
  }
  parser = OptionParser.new{|o|
    o.on('-e', '--executables [EXECUTABLES]',
         'Specify benchmark targets ("exec1; exec2; exec3, ...")'){|e|
      opt[:execs] = e.split(/;/)
    }
    o.on('-d', '--directory [DIRECTORY]'){|d|
      opt[:dir] = d
    }
    o.on('-p', '--pattern [PATTERN]', "Benchmark name pattern"){|p|
      opt[:pattern] = p
    }
    o.on('-n', '--repeat-num [NUM]', "Repeat count"){|n|
      opt[:repeat] = n.to_i
    }
    o.on('-q', '--quiet'){|q|
      opt[:quiet] = q
    }
    o.on('-v', '--verbose'){|v|
      opt[:verbose] = v
    }
  }

  parser.parse!(ARGV)
  BenchmarkDriver.benchmark(opt)
end

