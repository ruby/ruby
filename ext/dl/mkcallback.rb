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

def func_arg(x,i)
  ctype = DLTYPE[x][:ctype]
  "#{ctype} arg#{i}"
end

def func_args(types)
  t = []
  types[1..-1].each_with_index{|x,i| t.push(func_arg(x,i))}
  t.join(", ")
end

def funcall_args(types)
  num = types.length - 1
  if( num > 0 )
    t = []
    types[1..-1].each_with_index{|x,i| t.push(DLTYPE[x][:c2rb].call("arg#{i}"))}
    return num.to_s + ", " + t.join(", ")
  else
    return num.to_s
  end
end

def output_func(types, n = 0)
  func_name = "rb_dl_func#{types2num(types)}_#{n}"
  code =
    "#{func_name}(#{func_args(types)}) /* #{types2ctypes(types).inspect} */\n" +
    "{\n" +
    "  VALUE val, obj;\n" +
    "#ifdef DEBUG\n" +
    "  printf(\"#{func_name}()\\n\");\n" +
    "#endif\n" +
    "  obj = rb_hash_aref(DLFuncTable, INT2NUM(#{types2num(types)}));\n" +
    "  obj = rb_hash_aref(obj,INT2NUM(#{n}));\n" +
    "  val = rb_funcall(obj, id_call,\n" +
    "                   #{funcall_args(types)});\n"

  rtype = DLTYPE[types[0]][:ctype]
  rcode = DLTYPE[types[0]][:rb2c]
  if( rcode )
    code += "  return #{rcode.call('val')};\n"
  end

  code =
    rtype + "\n" +
    code +
    "}\n\n"
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
