#
# YARV benchmark driver
#

require 'benchmark'
require 'rbconfig'

$yarvonly = false
$rubyonly = false

$results  = []

# prepare 'wc.input'
def prepare_wc_input
  wcinput = File.join(File.dirname($0), 'wc.input')
  wcbase  = File.join(File.dirname($0), 'wc.input.base')
  unless FileTest.exist?(wcinput)
    data = File.read(wcbase)
    13.times{
      data << data
    }
    open(wcinput, 'w'){|f| f.write data}
  end
end

prepare_wc_input

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

def benchmark file, bin
  m = Benchmark.measure{
    `#{bin} #{$opts} #{file}`
  }
  sec = '%.3f' % m.real
  puts " #{sec}"
  sec
end

def ruby_exec file
  print 'ruby'
  benchmark file, $ruby_program
end

def yarv_exec file
  print 'yarv'
  benchmark file, $yarv_program
end

if $0 == __FILE__
  ARGV.each{|arg|
    case arg
    when /\A--yarv-program=(.+)/
      $yarv_program = $1
    when /\A--ruby-program=(.+)/
      $ruby_program = $1
    when /\A--opts=(.+)/
      $opts = $1
    when /\A(--yarv)|(-y)/
      $yarvonly = true
    when /\A(--ruby)|(-r)/
      $rubyonly = true
    end
  }
  ARGV.delete_if{|arg|
    /\A-/ =~ arg
  }
  
  puts "Ruby:"
  system("#{$ruby_program} -v")
  puts
  puts "YARV:"
  system("#{$yarv_program} -v")

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

