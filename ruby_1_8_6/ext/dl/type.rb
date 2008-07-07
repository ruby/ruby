# example:
#  DLTYPE[INT][:rb2c]["arg0"] => "NUM2INT(arg0)"
#  DLTYPE[DOUBLE][:c2rb]["r"] => "rb_float_new(r)"

DLTYPE = {
  VOID  = 0x00 => {
    :name => 'VOID',
    :rb2c => nil,
    :c2rb => nil,
    :ctype => "void",
    :stmem => "v",
    :sym => true,
    :cb => true,
  },
  CHAR  = 0x01 => {
    :name => 'CHAR',
    :rb2c => proc{|x| "NUM2CHR(#{x})"},
    :c2rb => proc{|x| "CHR2FIX(#{x})"},
    :ctype => "char",
    :stmem => "c",
    :sym => false,
    :cb => false,
  },
  SHORT = 0x02 => {
    :name => 'SHORT',
    :rb2c => proc{|x| "FIX2INT(#{x})"},
    :c2rb => proc{|x| "INT2FIX(#{x})"},
    :ctype => "short",
    :stmem => "h",
    :sym => false,
    :cb => false,
  },
  INT   = 0x03 => {
    :name => 'INT',
    :rb2c => proc{|x| "NUM2INT(#{x})"},
    :c2rb => proc{|x| "INT2NUM(#{x})"},
    :ctype => "int",
    :stmem => "i",
    :sym => true,
    :cb => false,
  },
  LONG  = 0x04 => {
    :name => 'LONG',
    :rb2c => proc{|x| "NUM2INT(#{x})"},
    :c2rb => proc{|x| "INT2NUM(#{x})"},
    :ctype => "long",
    :stmem => "l",
    :sym => true,
    :cb => true,
  },
  FLOAT = 0x05 => {
    :name => 'FLOAT',
    :rb2c => proc{|x| "(float)(RFLOAT(#{x})->value)"},
    :c2rb => proc{|x| "rb_float_new((double)#{x})"},
    :ctype => "float",
    :stmem => "f",
    :sym => false,
    :cb => false,
  },
  DOUBLE = 0x06 => {
    :name => 'DOUBLE',
    :rb2c => proc{|x| "RFLOAT(#{x})->value"},
    :c2rb => proc{|x| "rb_float_new(#{x})"},
    :ctype => "double",
    :stmem => "d",
    :sym => true,
    :cb => true,
  },
  VOIDP = 0x07 => {
    :name => 'VOIDP',
    :rb2c => proc{|x| "rb_dlptr2cptr(#{x})"},
    :c2rb => proc{|x| "rb_dlptr_new(#{x},sizeof(void*),0)"},
    :ctype => "void *",
    :stmem => "p",
    :sym => true,
    :cb => true,
  },
}

def tpush(t, x)
  (t << 3)|x
end

def tget(t, i)
  (t & (0x07 << (i * 3))) >> (i * 3)
end

def types2num(types)
  res = 0x00
  r = types.reverse
  r.each{|t|
    res = tpush(res,t)
  }
  res
end

def num2types(num)
  ts = []
  i  = 0
  t = tget(num,i)
  while( (t != VOID && i > 0) || (i == 0) )
    ts.push(DLTYPE[t][:ctype])
    i += 1
    t = tget(num,i)
  end
  ts
end

def types2ctypes(types)
  res = []
  types.each{|t|
    res.push(DLTYPE[t][:ctype])
  }
  res
end
