# -*- ruby -*-

require 'mkmf'
$:.unshift File.dirname(__FILE__)
require 'type'
require 'dlconfig'

def output_arg(x,i)
  "args[#{i}].#{DLTYPE[x][:stmem]}"
end

def output_args(types)
  t = []
  types[1..-1].each_with_index{|x,i| t.push(output_arg(x,i))}
  t.join(",")
end

def output_callfunc(types)
  t = types[0]
  stmem = DLTYPE[t][:stmem]
  ctypes = types2ctypes(types)
  if( t == VOID )
    callstm = "(*f)(#{output_args(types)})"
  else
    callstm = "ret.#{stmem} = (*f)(#{output_args(types)})"
  end
  [ "{",
    "#{ctypes[0]} (*f)(#{ctypes[1..-1].join(',')}) = func;",
    "#{callstm};",
    "}"].join(" ")
end

def output_case(types)
  num = types2num(types)
  callfunc_stm = output_callfunc(types)
<<EOF
  case #{num}:
#ifdef DEBUG
    printf("#{callfunc_stm}\\n");
#endif
    #{callfunc_stm};
    break;
EOF
end

def rec_output(types = [VOID])
  print output_case(types)
  if( types.length <= MAX_ARG )
    DLTYPE.keys.sort.each{|t|
      if( t != VOID && DLTYPE[t][:sym] )
	rec_output(types + [t])
      end
    }
  end
end

DLTYPE.keys.sort.each{|t|
  if( DLTYPE[t][:sym] )
    $stderr.printf("  #{DLTYPE[t][:ctype]}\n")
    rec_output([t])
  end
}
