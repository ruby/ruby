# -*- ruby -*-

require 'mkmf'
$:.unshift File.dirname(__FILE__)
require 'type'
require 'dlconfig'

$int_eq_long = try_run(<<EOF)
int main() {
  return sizeof(int) == sizeof(long) ? 0 : 1;
}
EOF

def output_func(types, n = 0)
  code =
    "/* #{types2ctypes(types).inspect} */\n" +
    "rb_dl_func_table[#{types2num(types)}][#{n}] " +
    "= rb_dl_func#{types2num(types)}_#{n};\n"
  if( n < MAX_CBENT - 1)
    return code + output_func(types, n+1)
  else
    return code
  end
end


def rec_output(types = [VOID])
  print output_func(types)
  if( types.length <= MAX_CBARG )
    DLTYPE.keys.sort.each{|t|
      if( t != VOID && DLTYPE[t][:cb] )
	rec_output(types + [t])
      end
    }
  end
end

DLTYPE.keys.sort.each{|t|
  if( DLTYPE[t][:cb] )
    rec_output([t])
  end
}
