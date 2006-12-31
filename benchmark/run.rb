#
# YARV benchmark driver
#

require 'yarvutil'
require 'benchmark'
require 'rbconfig'

$yarvonly = false
$rubyonly = false

$results  = []

puts "ruby #{RUBY_VERSION} #{RUBY_PLATFORM}(#{RUBY_RELEASE_DATE})"
puts YARVCore::VERSION + " rev: #{YARVCore::REV} (#{YARVCore::DATE})"
puts YARVCore::OPTS
puts

def bm file
  prog = File.read(file).map{|e| e.rstrip}.join("\n")
  return if prog.empty?

  /[a-z]+_(.+)\.rb/ =~ file
  bm_name = $1
  puts '-----------------------------------------------------------' unless $yarvonly || $rubyonly
  puts "#{bm_name}: "
  
  
puts <<EOS unless $yarvonly || $rubyonly
#{prog}
--
EOS
  #iseq = YARVUtil.parse(File.read(file))
  #vm   = YARVCore::VM.new
  begin
    Benchmark.bm{|x|
    # x.report("yarv"){ YARVUtil.load_bm(file) }
    } unless $yarvonly || $rubyonly

    result = [bm_name]
    result << ruby_exec(file) unless $yarvonly
    result << yarv_exec(file) unless $rubyonly
    $results << result
    
    # puts YARVUtil.parse(File.read(file), file, 1).disasm
    
    # x.report("ruby"){ load(file, false)    }
    # x.report("yarv"){ vm.eval iseq }
  rescue Exception => e
    puts
    puts "** benchmark failure: #{e}"
    puts e.backtrace
  end
end

def exec_command type, file, w
  <<-EOP
  $DRIVER_PATH = '#{File.dirname($0)}'
  $LOAD_PATH.replace $LOAD_PATH | #{$LOAD_PATH.inspect}
  require 'benchmark'
  require 'yarvutil'
  print '#{type}'
  begin
    puts Benchmark.measure{
      #{w}('#{file}')
    }
  rescue Exception => exec_command_error_variable
    puts "\t" + exec_command_error_variable.message
  end
  EOP
end

def benchmark prog
  rubybin = ENV['RUBY'] || File.join(
    Config::CONFIG["bindir"],
    Config::CONFIG["ruby_install_name"] + Config::CONFIG["EXEEXT"])

  #
  tmpfile = Tempfile.new('yarvbench')
  tmpfile.write(prog)
  tmpfile.close

  cmd = "#{rubybin} #{tmpfile.path}"
  result = `#{cmd}`
  puts result
  tmpfile.close(true)
  result
end

def ruby_exec file
  prog = exec_command 'ruby', file, 'load'
  benchmark prog
end

def yarv_exec file
  prog = exec_command 'yarv', file, 'YARVUtil.load_bm'
  benchmark prog
end

if $0 == __FILE__
  ARGV.each{|arg|
    if /\A(--yarv)|(-y)/ =~ arg
      $yarvonly = true
    elsif /\A(--ruby)|(-r)/ =~ arg
      $rubyonly = true
    end
  }
  ARGV.delete_if{|arg|
    /\A-/ =~ arg
  }
  
  if ARGV.empty?
    Dir.glob(File.dirname(__FILE__) + '/bm_*.rb').sort.each{|file|
      bm file
    }
  else
    ARGV.each{|file|
      Dir.glob(File.join(File.dirname(__FILE__), file + '*')){|ef|
        # file = "#{File.dirname(__FILE__)}/#{file}.rb"
        bm ef
      }
    }
  end

  puts
  puts "-- benchmark summary ---------------------------"
  $results.each{|res|
    print res.shift, "\t"
    (res||[]).each{|result|
      /([\d\.]+)/ =~ result
      print $1 + "\t" if $1
    }
    puts
  }
end


