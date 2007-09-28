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
      v.sub!(/ patchlevel \d+/, '')
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
      @start_time = Time.now
      puts @start_time
      @execs.each_with_index{|(e, v), i|
        puts "target #{i}: #{v}"
      }
    end
  end

  def show_results
    puts
    if @verbose
      puts '-----------------------------------------------------------'
      puts 'raw data:'
      pp @results

      puts
      puts "Elapesed time: #{Time.now - @start_time} (sec)"
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

  def files
    flag = {}
    vm1 = vm2 = wl1 = wl2 = false
    @files = Dir.glob(File.join(@dir, 'bm*.rb')).map{|file|
      next if @pattern && /#{@pattern}/ !~ File.basename(file)
      case file
      when /bm_(vm[12])_/, /bm_loop_(whileloop2?).rb/
        flag[$1] = true
      end
      file
    }.compact

    if flag['vm1'] && !flag['whileloop']
      @files << File.join(@dir, 'bm_loop_whileloop.rb')
    elsif flag['vm2'] && !flag['whileloop2']
      @files << File.join(@dir, 'bm_loop_whileloop2.rb')
    end

    @files.sort!
    STDERR.puts "total: #{@files.size * @repeat} trial(s) (#{@repeat} trial(s) for #{@files.size} benchmark(s))"
    @files
  end

  def run
    files.each_with_index{|file, i|
      @i = i
      r = measure_file(file)

      if /bm_loop_whileloop.rb/ =~ file
        @loop_wl1 = r[1].map{|e| e.min}
      elsif /bm_loop_whileloop2.rb/ =~ file
        @loop_wl2 = r[1].map{|e| e.min}
      end
    }
  end

  def measure_file file
    name = File.basename(file, '.rb').sub(/^bm_/, '')
    prepare_file = File.join(File.dirname(file), "prepare_#{name}.rb")
    load prepare_file if FileTest.exist?(prepare_file)

    if @verbose
      puts
      puts '-----------------------------------------------------------'
      puts name
      puts File.read(file)
      puts
    end

    result = [name]
    result << @execs.map{|(e, v)|
      (0...@repeat).map{
        if @verbose
          print "#{v}\t"
          STDOUT.flush
        end

        if !@verbose || !STDOUT.tty?
          STDERR.print '.'
          STDERR.flush
        end

        m = measure e, file
        puts "#{m}" if @verbose
        m
      }
    }
    @results << result
    result
  end

  def measure executable, file

    cmd = "#{executable} #{file}"
    m = Benchmark.measure{
      `#{cmd}`
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
    o.on('-e', '--executables [EXECS]',
         "Specify benchmark one or more targets. (exec1; exec2; exec3, ...)"){|e|
      opt[:execs] = e.split(/;/)
    }
    o.on('-d', '--directory [DIRECTORY]', "Benchmark directory"){|d|
      opt[:dir] = d
    }
    o.on('-p', '--pattern [PATTERN]', "Benchmark name pattern"){|p|
      opt[:pattern] = p
    }
    o.on('-r', '--repeat-count [NUM]', "Repeat count"){|n|
      opt[:repeat] = n.to_i
    }
    o.on('-q', '--quiet', "Run without notify information except result table."){|q|
      opt[:quiet] = q
    }
    o.on('-v', '--verbose'){|v|
      opt[:verbose] = v
    }
  }

  parser.parse!(ARGV)
  BenchmarkDriver.benchmark(opt)
end

