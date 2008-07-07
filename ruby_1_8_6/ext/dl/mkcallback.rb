# -*- ruby -*-

require 'mkmf'
$:.unshift File.dirname(__FILE__)
require 'type'
require 'dlconfig'

def mkfunc(rettype, fnum, argc)
  args = (0..(argc-1)).collect{|i| "long arg#{i}"}.join(", ")

  subst_code = (0..(argc-1)).collect{|i|
    "  buff[#{i.to_s}] = arg#{i.to_s};"
  }.join("\n")

  ret_code =
    if( DLTYPE[rettype][:c2rb] )
      "  return #{DLTYPE[rettype][:rb2c]['retval']};"
    else
      "  /* no return value */"
    end

  code = [
    "static #{DLTYPE[rettype][:ctype]}",
    "rb_dl_callback_func_#{rettype.to_s}_#{fnum.to_s}(#{args})",
    "{",
    "  VALUE retval, proto, proc, obj;",
    "  VALUE argv[#{argc.to_s}];",
    "  int  argc;",
    "  long buff[#{argc.to_s}];",
    "",
    subst_code,
    "",
    "  obj = rb_hash_aref(DLFuncTable, rb_assoc_new(INT2NUM(#{rettype.to_s}),INT2NUM(#{fnum.to_s})));",
    "  if(NIL_P(obj))",
    "    rb_raise(rb_eDLError, \"callback function does not exist in DL::FuncTable\");",
    "  Check_Type(obj, T_ARRAY);",
    "  proto = rb_ary_entry(obj, 0);",
    "  proc  = rb_ary_entry(obj, 1);",
    "  Check_Type(proto, T_STRING);",
    "  if( RSTRING(proto)->len >= #{argc.to_s} )",
    "    rb_raise(rb_eArgError, \"too many arguments\");",
    "  rb_dl_scan_callback_args(buff, RSTRING(proto)->ptr, &argc, argv);",
    "  retval = rb_funcall2(proc, id_call, argc, argv);",
    "",
    ret_code,
    "}",
  ].join("\n")

  return code
end

DLTYPE.keys.sort.each{|t|
  for n in 0..(MAX_CALLBACK - 1)
    print(mkfunc(t, n, 15), "\n\n")
  end
}
