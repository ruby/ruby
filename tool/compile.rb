require 'optparse'
require 'pp'

OutputCompileOption = {
  # enable
  :peephole_optimization    =>true,
  :inline_const_cache       =>true,
  
  # disable
  :specialized_instruction  =>false,
  :operands_unification     =>false,
  :instructions_unification =>false,
  :stack_caching            =>false,
}

def compile_to_rb infile, outfile
  iseq = YARVCore::InstructionSequence.compile_file(infile, OutputCompileOption)

  open(outfile, 'w'){|f|
    f.puts "YARVCore::InstructionSequence.load(" +
           "Marshal.load(<<EOS____.unpack('m*')[0])).eval"
    f.puts [Marshal.dump(iseq.to_a)].pack('m*')
    f.puts "EOS____"
  }
end

def compile_to_rbc infile, outfile, type
  iseq = YARVCore::InstructionSequence.compile_file(infile, OutputCompileOption)

  case type
  when 'm'
    open(outfile, 'wb'){|f|
      f.print "RBCM"
      f.puts Marshal.dump(iseq.to_a, f)
    }
  else
    raise "Unsupported compile type: #{type}"
  end
end

## main

outfile = 'a.rb'
type    = 'm'
opt = OptionParser.new{|opt|
  opt.on('-o file'){|o|
    outfile = o
  }
  opt.on('-t type', '--type type'){|o|
    type = o
  }
  opt.version = '0.0.1'
}

opt.parse!(ARGV)

ARGV.each{|file|
  case outfile
  when /\.rb\Z/
    compile_to_rb file, outfile
  when /\.rbc\Z/
    compile_to_rbc file, outfile, type
  else
    raise
  end
}

