#
# Ruby Benchmark driver
#

first = true

begin
  require 'optparse'
rescue LoadError
  if first
    first = false
    $:.unshift File.join(File.dirname(__FILE__), '../lib')
    retry
  else
    raise
  end
end

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

  def output *args
    puts(*args)
    @output and @output.puts(*args)
  end

  def message *args
    output(*args) if @verbose
  end

  def message_print *args
    if @verbose
      print(*args)
      STDOUT.flush
      @output and @output.print(*args)
    end
  end

  def progress_message *args
    unless STDOUT.tty?
      STDERR.print(*args)
      STDERR.flush
    end
  end

  def initialize execs, dir, opt = {}
    @execs = execs.map{|e|
      e.strip!
      next if e.empty?

      if /(.+)::(.+)/ =~ e
        # ex) ruby-a::/path/to/ruby-a
        label = $1.strip
        path = $2
        version = `#{path} -v`.chomp
      else
        path = e
        version = label = `#{path} -v`.chomp
      end
      [path, label, version]
    }.compact

    @dir = dir
    @repeat = opt[:repeat] || 1
    @repeat = 1 if @repeat < 1
    @pattern = opt[:pattern] || nil
    @exclude = opt[:exclude] || nil
    @verbose = opt[:quiet] ? false : (opt[:verbose] || false)
    @output = opt[:output] ? open(opt[:output], 'w') : nil
    @loop_wl1 = @loop_wl2 = nil
    @ruby_arg = opt[:ruby_arg] || nil
    @opt = opt

    # [[name, [[r-1-1, r-1-2, ...], [r-2-1, r-2-2, ...]]], ...]
    @results = []

    if @verbose
      @start_time = Time.now
      message @start_time
      @execs.each_with_index{|(path, label, version), i|
        message "target #{i}: " + (label == version ? "#{label}" : "#{label} (#{version})") + " at \"#{path}\""
      }
    end
  end

  def adjusted_results name, results
    s = nil
    results.each_with_index{|e, i|
      r = e.min
      case name
      when /^vm1_/
        if @loop_wl1
          r -= @loop_wl1[i]
          r = 0 if r < 0
          s = '*'
        end
      when /^vm2_/
        if @loop_wl2
          r -= @loop_wl2[i]
          r = 0 if r < 0
          s = '*'
        end
      end
      yield r
    }
    s
  end

  def show_results
    output

    if @verbose
      message '-----------------------------------------------------------'
      message 'raw data:'
      message
      message PP.pp(@results, "", 79)
      message
      message "Elapsed time: #{Time.now - @start_time} (sec)"
    end

    output '-----------------------------------------------------------'
    output 'benchmark results:'

    if @verbose and @repeat > 1
      output "minimum results in each #{@repeat} measurements."
    end

    output "Execution time (sec)"
    output "name\t#{@execs.map{|(_, v)| v}.join("\t")}"
    @results.each{|v, result|
      rets = []
      s = adjusted_results(v, result){|r|
        rets << sprintf("%.3f", r)
      }
      output "#{v}#{s}\t#{rets.join("\t")}"
    }

    if @execs.size > 1
      output
      output "Speedup ratio: compare with the result of `#{@execs[0][1]}' (greater is better)"
      output "name\t#{@execs[1..-1].map{|(_, v)| v}.join("\t")}"
      @results.each{|v, result|
        rets = []
        first_value = nil
        s = adjusted_results(v, result){|r|
          if first_value
            if r == 0
              rets << "Error"
            else
              rets << sprintf("%.3f", first_value/r)
            end
          else
            first_value = r
          end
        }
        output "#{v}#{s}\t#{rets.join("\t")}"
      }
    end

    if @opt[:output]
      output
      output "Log file: #{@opt[:output]}"
    end
  end

  def files
    flag = {}
    @files = Dir.glob(File.join(@dir, 'bm*.rb')).map{|file|
      next if @pattern && /#{@pattern}/ !~ File.basename(file)
      next if @exclude && /#{@exclude}/ =~ File.basename(file)
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
    progress_message "total: #{@files.size * @repeat} trial(s) (#{@repeat} trial(s) for #{@files.size} benchmark(s))\n"
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
      output
      output '-----------------------------------------------------------'
      output name
      output
      output File.read(file)
      output
    end

    result = [name]
    result << @execs.map{|(e, v)|
      (0...@repeat).map{
        message_print "#{v}\t"
        progress_message '.'

        m = measure(e, file)
        message "#{m}"
        m
      }
    }
    @results << result
    result
  end

  def measure executable, file
    cmd = "#{executable} #{@ruby_arg} #{file}"

    m = Benchmark.measure{
      `#{cmd}`
    }

    if $? != 0
      output "\`#{cmd}\' exited with abnormal status (#{$?})"
      0
    else
      m.real
    end
  end
end

if __FILE__ == $0
  opt = {
    :execs => [],
    :dir => File.dirname(__FILE__),
    :repeat => 1,
    :output => "bmlog-#{Time.now.strftime('%Y%m%d-%H%M%S')}.#{$$}",
  }

  parser = OptionParser.new{|o|
    o.on('-e', '--executables [EXECS]',
      "Specify benchmark one or more targets (e1::path1; e2::path2; e3::path3;...)"){|e|
       e.split(/;/).each{|path|
         opt[:execs] << path
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
    o.on('-o', '--output-file [FILE]', "Output file"){|f|
      opt[:output] = f
    }
    o.on('--ruby-arg [ARG]', "Optional argument for ruby"){|a|
      opt[:ruby_arg] = a
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

