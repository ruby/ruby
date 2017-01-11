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
require 'tempfile'

class BenchmarkDriver
  def self.benchmark(opt)
    driver = self.new(opt[:execs], opt[:dir], opt)
    begin
      driver.run
    ensure
      driver.show_results
    end
  end

  def self.load(input, type, opt)
    case type
    when 'yaml'
      require 'yaml'
      h = YAML.load(input)
    when 'json'
      require 'json'
      h = JSON.load(input)
    else
      h = eval(input.read)
    end
    results = h[:results] || h["results"]
    obj = allocate
    obj.instance_variable_set("@execs", h[:executables] || h["executables"])
    obj.instance_variable_set("@results", results)
    obj.instance_variable_set("@opt", opt)
    [1, 2].each do |i|
      loop = results.assoc((n = "loop_whileloop#{i}").intern) || results.assoc(n)
      obj.instance_variable_set("@loop_wl#{i}", loop ? loop[1].map {|t,*|t} : nil)
    end
    obj.instance_variable_set("@measure_target", opt[:measure_target] || opt["measure_target"])
    obj
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
    @measure_target = opt[:measure_target]
    @opt = opt

    # [[name, [[r-1-1, r-1-2, ...], [r-2-1, r-2-2, ...]]], ...]
    @results = []

    if @verbose
      @start_time = Time.now
      message @start_time
      @execs.each_with_index{|(path, label, version), i|
        message "target #{i}: " + (label == version ? "#{label}" : "#{label} (#{version})") + " at \"#{path}\""
      }
      message "measure target: #{@measure_target}"
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
    case @opt[:format]
    when :tsv
      strformat = "\t%1$s"
      numformat = "\t%1$*2$.3f"
      minwidth = 0
      name_width = 0
    when :markdown
      markdown = true
      strformat = "|%1$-*2$s"
      numformat = "|%1$*2$.3f"
    when :plain
      strformat = " %1$-*2$s"
      numformat = " %1$*2$.3f"
    end

    name_width ||= @results.map {|v, result|
      v.size + (case v; when /^vm1_/; @loop_wl1; when /^vm2_/; @loop_wl2; end ? 1 : 0)
    }.max
    minwidth ||= 7
    width = @execs.map{|(_, v)| [v.size, minwidth].max}

    output

    if @verbose
      message '-----------------------------------------------------------'
      message 'raw data:'
      message
      message PP.pp(@results, "", 79)
      message
      message "Elapsed time: #{Time.now - @start_time} (sec)"
    end

    if rawdata_output = @opt[:rawdata_output]
      h = {}
      h[:cpuinfo] = File.read('/proc/cpuinfo') if File.exist?('/proc/cpuinfo')
      h[:executables] = @execs
      h[:results] = @results
      if (type = File.extname(rawdata_output)).empty?
        type = rawdata_output
        rawdata_output = @output.path.sub(/\.[^.\/]+\z/, '') << '.' << rawdata_output
      end
      case type
      when 'yaml'
        require 'yaml'
        h = YAML.dump(h)
      when 'json'
        require 'json'
        h = JSON.pretty_generate(h)
      else
        require 'pp'
        h = h.pretty_inspect
      end
      open(rawdata_output, 'w') {|f| f.puts h}
    end

    output '-----------------------------------------------------------'
    output 'benchmark results:'

    if @verbose and @repeat > 1
      output "minimum results in each #{@repeat} measurements."
    end

    output({
      real: "Execution time (sec)",
      peak: "Memory usage (peak) (B)",
      size: "Memory usage (last size) (B)",
    }[@measure_target])
    output if markdown
    output ["name".ljust(name_width), @execs.map.with_index{|(_, v), i| sprintf(strformat, v, width[i])}].join("").rstrip
    output ["-"*name_width, width.map{|n|":".rjust(n, "-")}].join("|") if markdown
    @results.each{|v, result|
      rets = []
      s = adjusted_results(v, result){|r|
        rets << sprintf(numformat, r, width[rets.size])
      }
      v += s if s
      output [v.ljust(name_width), rets].join("")
    }

    if @execs.size > 1
      output
      output({
        real: "Speedup ratio: compare with the result of `#{@execs[0][1]}' (greater is better)",
        peak: "Memory consuming ratio (peak) with the result of `#{@execs[0][1]}' (greater is better)",
        size: "Memory consuming ratio (size) with the result of `#{@execs[0][1]}' (greater is better)",
      }[@measure_target])
      output if markdown
      output ["name".ljust(name_width), @execs[1..-1].map.with_index{|(_, v), i| sprintf(strformat, v, width[i])}].join("").rstrip
      output ["-"*name_width, width[1..-1].map{|n|":".rjust(n, "-")}].join("|") if markdown
      @results.each{|v, result|
        rets = []
        first_value = nil
        s = adjusted_results(v, result){|r|
          if first_value
            if r == 0
              rets << "Error"
            else
              rets << sprintf(numformat, first_value/Float(r), width[rets.size+1])
            end
          else
            first_value = r
          end
        }
        v += s if s
        output [v.ljust(name_width), rets].join("")
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

  unless defined?(File::NULL)
    if File.exist?('/dev/null')
      File::NULL = '/dev/null'
    end
  end

  def measure executable, file
    case @measure_target
    when :real
      cmd = "#{executable} #{@ruby_arg} #{file}"
      m = Benchmark.measure{
        system(cmd, out: File::NULL)
      }
      result = m.real
    when :peak, :size
      tmp = Tempfile.new("benchmark-memory-wrapper-data")
      wrapper = "#{File.join(__dir__, 'memory_wrapper.rb')} #{tmp.path} #{@measure_target}"
      cmd = "#{executable} #{@ruby_arg} #{wrapper} #{file}"
      system(cmd, out: File::NULL)
      result = tmp.read.to_i
      tmp.close
    else
      raise "unknown measure target"
    end

    if $? != 0
      raise $?.inspect if $? && $?.signaled?
      output "\`#{cmd}\' exited with abnormal status (#{$?})"
      0
    else
      result
    end
  end
end

if __FILE__ == $0
  opt = {
    :execs => [],
    :dir => File.dirname(__FILE__),
    :repeat => 1,
    :measure_target => :real,
    :output => nil,
    :raw_output => nil,
    :format => :tsv,
  }
  formats = {
    :tsv => ".tsv",
    :markdown => ".md",
    :plain => ".txt",
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
    o.on('--measure-target [TARGET]', 'real (execution time), peak, size (memory)'){|mt|
      opt[:measure_target] = mt.to_sym
    }
    o.on('--rawdata-output [FILE]', 'output rawdata'){|r|
      opt[:rawdata_output] = r
    }
    o.on('--load-rawdata=FILE', 'input rawdata'){|r|
      opt[:rawdata_input] = r
    }
    o.on('-f', "--format=FORMAT", "output format (#{formats.keys.join(",")})", formats.keys){|r|
      opt[:format] = r
    }
    o.on('-v', '--verbose'){|v|
      opt[:verbose] = v
    }
    o.on('-q', '--quiet', "Run without notify information except result table."){|q|
      opt[:quiet] = q
      opt[:verbose] = false
    }
  }

  parser.parse!(ARGV)

  if input = opt[:rawdata_input]
    b = open(input) {|f|
      BenchmarkDriver.load(f, File.extname(input)[1..-1], opt)
    }
    b.show_results
  else
    opt[:output] ||= "bmlog-#{Time.now.strftime('%Y%m%d-%H%M%S')}.#{$$}#{formats[opt[:format]]}"
    BenchmarkDriver.benchmark(opt)
  end
end

