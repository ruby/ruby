# -*- ruby -*-

require 'dl'
require 'dl/import'

$FAIL = 0
$TOTAL = 0

def assert(label, ty, *conds)
  $TOTAL += 1
  cond = !conds.include?(false)
  if( cond )
    printf("succeed in `#{label}'\n")
  else
    $FAIL += 1
    case ty
    when :may
      printf("fail in `#{label}' ... expected\n")
    when :must
      printf("fail in `#{label}' ... unexpected\n")
    when :raise
      raise(RuntimeError, "fail in `#{label}'")
    end
  end
end

def debug(*xs)
  if( $DEBUG )
    xs.each{|x|
      p x
    }
  end
end

print("DLSTACK   = #{DL::DLSTACK}\n")
print("MAX_ARG   = #{DL::MAX_ARG}\n")
print("\n")
print("DL::FREE = #{DL::FREE.inspect}\n")
print("\n")

$LIB = nil
if( !$LIB && File.exist?("libtest.so") )
  $LIB = "./libtest.so"
end
if( !$LIB && File.exist?("test/libtest.so") )
  $LIB = "./test/libtest.so"
end

module LIBTest
  extend DL::Importable

  dlload($LIB)
  extern "int test_c2i(char)"
  extern "char test_i2c(int)"
  extern "long test_lcc(char, char)"
  extern "double test_f2d(float)"
  extern "float test_d2f(double)"
  extern "int test_strlen(char*)"
  extern "int test_isucc(int)"
  extern "long test_lsucc(long)"
  extern "void test_succ(long *)"
  extern "int test_arylen(int [])"
  extern "void test_append(char*[], int, char *)"
end

DL.dlopen($LIB){|h|
  c2i = h["test_c2i","IC"]
  debug c2i
  r,rs = c2i[?a]
  debug r,rs
  assert("c2i", :may, r == ?a)
  assert("extern c2i", :must, r == LIBTest.test_c2i(?a))

  i2c = h["test_i2c","CI"]
  debug i2c
  r,rs = i2c[?a]
  debug r,rs
  assert("i2c", :may, r == ?a)
  assert("exern i2c", :must, r == LIBTest.test_i2c(?a))

  lcc = h["test_lcc","LCC"]
  debug lcc
  r,rs = lcc[1,2]
  assert("lcc", :may, r == 3)
  assert("extern lcc", :must, r == LIBTest.test_lcc(1,2))

  f2d = h["test_f2d","DF"]
  debug f2d
  r,rs = f2d[20.001]
  debug r,rs
  assert("f2d", :may, r.to_i == 20)
  assert("extern f2d", :must, r = LIBTest.test_f2d(20.001))

  d2f = h["test_d2f","FD"]
  debug d2f
  r,rs = d2f[20.001]
  debug r,rs
  assert("d2f", :may, r.to_i == 20)
  assert("extern d2f", :must, r == LIBTest.test_d2f(20.001))

  strlen = h["test_strlen","IS"]
  debug strlen
  r,rs = strlen["0123456789"]
  debug r,rs
  assert("strlen", :must, r == 10)
  assert("extern strlen", :must, r == LIBTest.test_strlen("0123456789"))

  isucc = h["test_isucc","II"]
  debug isucc
  r,rs = isucc[2]
  debug r,rs
  assert("isucc", :must, r == 3)
  assert("extern isucc", :must, r == LIBTest.test_isucc(2))

  lsucc = h["test_lsucc","LL"]
  debug lsucc
  r,rs = lsucc[10000000]
  debug r,rs
  assert("lsucc", :must, r == 10000001)
  assert("extern lsucc", :must, r == LIBTest.test_lsucc(10000000))

  succ = h["test_succ","0l"]
  debug succ
  r,rs = succ[0]
  debug r,rs
  assert("succ", :must, rs[0] == 1)
  l = DL.malloc(DL.sizeof("L"))
  l.struct!("L",:lval)
  LIBTest.test_succ(l)
  assert("extern succ", :must, rs[0] == l[:lval])

  arylen = h["test_arylen","IA"]
  debug arylen
  r,rs = arylen[["a","b","c","d",nil]]
  debug r,rs
  assert("arylen", :must, r == 4)

  arylen = h["test_arylen","IP"]
  debug arylen
  r,rs = arylen[["a","b","c","d",nil]]
  debug r,rs
  assert("arylen", :must, r == 4)
  assert("extern arylen", :must, r == LIBTest.test_arylen(["a","b","c","d",nil]))

  append = h["test_append","0aIS"]
  debug append
  r,rs = append[["a","b","c"],3,"x"]
  debug r,rs
  assert("append", :must, rs[0].to_a('S',3) == ["ax","bx","cx"])

  LIBTest.test_append(["a","b","c"],3,"x")
  assert("extern append", :must, rs[0].to_a('S',3) == LIBTest._args_[0].to_a('S',3))

  strcat = h["test_strcat","SsS"]
  debug strcat
  r,rs = strcat["abc\0","x"]
  debug r,rs
  assert("strcat", :must, rs[0].to_s == "abcx")

  init = h["test_init","IiP"]
  debug init
  argc = 3
  argv = ["arg0","arg1","arg2"].to_ptr
  r,rs = init[argc, argv.ref]
  assert("init", :must, r == 0)
}


h = DL.dlopen($LIB)

sym_open = h["test_open", "PSS"]
sym_gets = h["test_gets", "SsIP"]
sym_close = h["test_close", "0P"]
debug sym_open,sym_gets,sym_close

line = "Hello world!\n"
File.open("tmp.txt", "w"){|f|
  f.print(line)
}

fp,rs = sym_open["tmp.txt", "r"]
if( fp )
  fp.free = sym_close
  r,rs = sym_gets[" " * 256, 256, fp]
  debug r,rs
  assert("open,gets", :must, rs[0] == line)
  ObjectSpace.define_finalizer(fp) {File.unlink("tmp.txt")}
  fp = nil
else
  assert("open,gets", :must, line == nil)
  File.unlink("tmp.txt")
end


callback1 = h["test_callback1"]
debug callback1
r,rs = h["test_call_func1", "IP"][callback1]
debug r,rs
assert("callback1", :must, r == 1)


callback2 = DL.callback("LLP"){|num,ptr|
  msg = ptr.to_s
  if( msg == "callback message" )
    2
  else
    0
  end
}
debug callback2
r,rs = h["test_call_func1", "IP"][callback2]
debug r,rs
assert("callback2", :must, r == 2)
DL.remove_callback(callback2)

ptr = DL.malloc(DL.sizeof('CL'))
ptr.struct!("CL", :c, :l)
ptr["c"] = 0
ptr["l"] = 0
r,rs = h["test_fill_test_struct","0PIL"][ptr,100,1000]
debug r,rs
assert("fill_test_struct", :must, ptr["c"] == 100, ptr["l"] == 1000)
assert("fill_test_struct", :must, ptr[:c] == 100, ptr[:l] == 1000) unless (Fixnum === :-)


r,rs = h["test_alloc_test_struct", "PIL"][100,200]
r.free = DL::FREE
r.struct!("CL", :c, :l)
assert("alloc_test_struct", :must, r["c"] == 100, r["l"] == 200)
assert("alloc_test_struct", :must, r[:c] == 100, r[:l] == 200) unless (Fixnum === :-)

ptr = h["test_strlen"]
sym1 = DL::Symbol.new(ptr,"foo","0")
sym2 = h["test_strlen","LS"]
assert("Symbol.new", :must, ptr == sym1.to_ptr, sym1.to_ptr == sym2.to_ptr)

set_val = h["test_set_long_value","0"]
get_val = h["test_get_long_value","L"]
lval = get_val[][0]
ptr = h["internal_long_value"]
ptr.struct!("L", :l)
assert("get value", :must, ptr["l"] == lval)
assert("get value", :must, ptr[:l] == lval) unless (Fixnum === :-)
ptr["l"] = 200
lval = get_val[][0]
assert("set value", :must, ptr["l"] == lval)
assert("set value", :must, ptr[:l] == lval) unless (Fixnum === :-)


data_init = h["test_data_init", "P"]
data_add  = h["test_data_add", "0PS"]
data_aref = h["test_data_aref", "PPI"]
r,rs = data_init[]
ptr = r
data_add[ptr, "name1"]
data_add[ptr, "name2"]
data_add[ptr, "name3"]

r,rs = data_aref[ptr, 1]
ptr = r
ptr.struct!("C1024P", :name, :next)
assert("data_aref", :must,
       ptr["name"].collect{|c| c.chr}.join.split("\0")[0] == "name2")
assert("data_aref", :must,
       ptr["name"].collect{|c| c.chr}.join.split("\0")[0] == "name2") unless (Fixnum === :-)

ptr = ptr["next"]
ptr.struct!("C1024P", :name, :next)
assert("data_aref", :must,
       ptr["name"].collect{|c| c.chr}.join.split("\0")[0] == "name1")
assert("data_aref", :must,
       ptr["name"].collect{|c| c.chr}.join.split("\0")[0] == "name1") unless (Fixnum === :-)

GC.start

ptr = DL::malloc(1024)
ptr.struct!("CHIL", "c", "h", "i", "l")
ptr["c"] = 1
ptr["h"] = 2
ptr["i"] = 3
ptr["l"] = 4
assert("struct!", :must,
       ptr["c"] == 1 &&
       ptr["h"] == 2 &&
       ptr["i"] == 3 &&
       ptr["l"] == 4)

ptr = DL::malloc(DL::sizeof("IP"))
ptr.struct!("IP", "n", "ptr")
ptr["n"] = 10
ptr["ptr"] = nil
assert("struct!", :must, ptr["n"] == 10 && ptr["ptr"] == nil)

GC.start
printf("fail/total = #{$FAIL}/#{$TOTAL}\n")
