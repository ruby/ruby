#! /usr/local/bin/ruby

$testnum=0

def check(what)
  printf "%s\n", what
  $what = what
  $testnum = 0
end

def ok
  $testnum+=1
  printf "ok %d\n", $testnum
end

def notok
  $testnum+=1
  printf "not ok %s %d\n", $what, $testnum
  $failed = TRUE
end

# make sure conditional operators work

check "condition"

$x = '0';

$x == $x && ok
$x != $x && notok
$x == $x || notok
$x != $x || ok

# first test to see if we can run the tests.

check "if";

$x = 'test';
if $x == $x then ok else notok end
if $x != $x then notok else ok end

check "case"

case 5
when 1, 2, 3, 4, 6, 7, 8
  notok
when 5
  ok
end

case 5
when 5
  ok
when 1..10
  notok
end

case 5
when 5
  ok
else
  notok
end

case "foobar"
when /^f.*r$/
  ok
else
  notok
end

check "while";

tmp = open("while_tmp", "w")
tmp.print "tvi925\n";
tmp.print "tvi920\n";
tmp.print "vt100\n";
tmp.print "Amiga\n";
tmp.print "paper\n";
tmp.close

# test break

tmp = open("while_tmp", "r")

while tmp.gets()
  break if /vt100/
end

if !tmp.eof && /vt100/ then
  ok
else
  notok
end
tmp.close

# test continue
$bad = FALSE
tmp = open("while_tmp", "r")
while tmp.gets()
    continue if /vt100/;
    $bad = 1 if /vt100/;
end
if !tmp.eof || /vt100/ || $bad
  notok
else
  ok
end
tmp.close

# test redo
$bad = FALSE
tmp = open("while_tmp", "r")
while tmp.gets()
  if gsub!('vt100', 'VT100')
    gsub!('VT100', 'Vt100')
    redo;
  end
  $bad = 1 if /vt100/;
  $bad = 1 if /VT100/;
end
if !tmp.eof || $bad
  notok
else
  ok
end
tmp.close

# test interval
$bad = FALSE
tmp = open("while_tmp", "r")
while tmp.gets()
  break if not 1..2
  if /vt100/ || /Amiga/ || /paper/
    $bad = TRUE
    notok
    break
  end
end
ok if not $bad
tmp.close

File.unlink "while_tmp" or `/bin/rm -f "while_tmp"`

# exception handling
check "exception";

begin
  fail "this must be handled"
  notok
rescue
  ok
end

$bad = TRUE
begin
  fail "this must be handled no.2"
rescue
  if $bad
    $bad = FALSE
    retry
    notok
  end
end
ok

$bad = TRUE
$string = "this must be handled no.3"
begin
  fail $string
rescue
ensure
  $bad = FALSE
  ok
end
notok if $bad || $! != $string

# exception in rescue clause
begin
  begin
    fail "this must be handled no.4"
  rescue 
    fail "exception in rescue clause"
  end
  notok
rescue
  ok
end
  
check "array"
$x = [0, 1, 2, 3, 4, 5]
if $x[2] == 2
  ok
else
  notok
end

if $x[1..3] == [1, 2, 3]
  ok
else
  notok
end

if $x[1,3] == [1, 2, 3]
  ok
else
  notok
end

if [1, 2] + [3, 4] == [1, 2, 3, 4]
  ok
else
  notok
end

$x[0, 2] = 10
if $x[0] == 10 && $x[1] == 2
  ok
else
  notok
end
  
$x[0, 0] = -1
if $x[0] == -1 && $x[1] == 10
  ok
else
  notok
end

$x[-1, 1] = 20
if $x[-1] == 20 && $x.pop == 20
  ok
else
  notok
end

$x = ["it", "came", "to", "pass", "that", "..."]
$x = $x.sort.join(" ")
if $x == "... came it pass that to"
  ok
else
  notok
end

# split test
if "1 byte string".split(//).reverse.join(":") == "g:n:i:r:t:s: :e:t:y:b: :1"
  ok
else
  notok
end

$x = [1]
if ($x * 5).join(":") == '1:1:1:1:1' then ok else notok end
if ($x * 1).join(":") == '1' then ok else notok end
if ($x * 0).join(":") == '' then ok else notok end

check "hash"
$x = {1=>2, 2=>4, 3=>6}
$y = {1, 2, 2, 4, 3, 6}

if $x[1] == 2
  ok
else
  notok
end

begin
  for k,v in $y
    fail if k*2 != v
  end
  ok
rescue
  notok
end

if $x.length == 3
  ok
else
  notok
end

if $x.has_key?(1)
  ok
else
  notok
end

if $x.has_value?(4)
  ok
else
  notok
end

if $x.indexes(2,3) == [4,6]
  ok
else
  notok
end

$z = $y.keys.join(":")
if $z == "1:2:3"
  ok
else
  notok
end

$z = $y.values.join(":")
if $z == "2:4:6"
  ok
else
  notok
end

if $x == $y
  ok
else
  notok
end

$y.shift
if $y.length == 2
  ok
else
  notok
end

check "iterator"

if iterator? then notok else ok end

def ttt
  if iterator? then ok else notok end
end
ttt{}

# yield at top level
begin
  yield
  notok
rescue
  ok
end

$x = [1, 2, 3, 4]
$y = []

# iterator over array
for i in $x
  $y.push i
end
if $x == $y
  ok
else
  notok
end

# nested iterator
def tt
  1.upto(10) {|i|
    yield i
  }
end

tt{|i| break if i == 5}
if i == 5
  ok
else
  notok
end

# iterator break/redo/continue/retry
done = TRUE
loop{
  break
  done = FALSE
  notok
}
ok if done

done = TRUE
$bad = FALSE
loop {
  break if not done
  done = FALSE
  continue
  $bad = TRUE
}
if $bad
  notok
else
  ok
end

done = TRUE
$bad = FALSE
loop {
  break if not done
  done = FALSE
  redo
  $bad = TRUE
}
if $bad
  notok
else
  ok
end

$x = []
for i in 1 .. 7
  $x.push(i)
end
if $x.size == 7
  ok
else
  notok
end
# $x == [1, 2, 3, 4, 5, 6, 7]
$done = FALSE
$x = []
for i in 1 .. 7			# see how retry works in iterator loop
  if i == 4 and not $done
    $done = TRUE
    retry
  end
  $x.push(i)
end
# $x == [1, 2, 3, 1, 2, 3, 4, 5, 6, 7]
if $x.size == 10
  ok
else
  notok
end

check "bignum"
def fact(n)
  return 1 if n == 0
  return n*fact(n-1)
end
if fact(40) == 815915283247897734345611269596115894272000000000
  ok
else
  notok
end
if fact(40) == 815915283247897734345611269596115894272000000001
  notok
else
  ok
end

check "string & char"

if "abcd" == "abcd"
  ok
else
  notok
end

if "abcd" =~ "abcd"
  ok
else
  notok
end

$foo = "abc"
if "#$foo = abc" == "abc = abc"
  ok
else
  notok
end

if "#{$foo} = abc" == "abc = abc"
  ok
else
  notok
end

foo = "abc"
if "#{foo} = abc" == "abc = abc"
  ok
else
  notok
end

if '-' * 5 == '-----' then ok else notok end
if '-' * 1 == '-' then ok else notok end
if '-' * 0 == '' then ok else notok end

foo = '-'
if foo * 5 == '-----' then ok else notok end
if foo * 1 == '-' then ok else notok end
if foo * 0 == '' then ok else notok end

# character constants(assumes ASCII)
if "a"[0] == ?a
  ok
else
  notok
end

if ?a == ?a
  ok
else
  notok
end

if ?\C-a == 1
  ok
else
  notok
end

if ?\M-a == 225
  ok
else
  notok
end

if ?\M-\C-a == 129
  ok
else
  notok
end

$x = "abcdef"
$y = [ ?a, ?b, ?c, ?d, ?e, ?f ]
$bad = FALSE
$x.each_byte {|i|
  if i != $y.shift
    $bad = TRUE
    break
  end
}
if not $bad
  ok
else
  notok
end

check "asignment"
a = nil
if a == nil
  ok
else
  notok
end

a, b = 1, 2
if a == 1 and b == 2 then
  ok
else
  notok
end

a, *b = 1, 2, 3
if a == 1 and b == [2, 3] then
  ok
else
  notok
end

check "call"
def aaa(a, b=100, *rest)
  res = [a, b]
  res += rest if rest
  return res
end

begin
  aaa()
  notok
rescue
  ok
end

begin
  aaa
  notok
rescue
  ok
end

begin
  if aaa(1) == [1, 100]
    ok
  else
    fail
  end
rescue
  notok
end

begin
  if aaa(1, 2) == [1, 2]
    ok
  else
    fail
  end
rescue
  notok
end

begin
  if aaa(1, 2, 3, 4) == [1, 2, 3, 4]
    ok
  else
    fail
  end
rescue
  notok
end

begin
  if aaa(1, *[2, 3, 4]) == [1, 2, 3, 4]
    ok
  else
    fail
  end
rescue
  notok
end

check "proc"
$proc = proc{|i| i}
if $proc.call(2) == 2
  ok
else
  notok
end

$proc = proc{|i| i*2}
if $proc.call(2) == 4
  ok
else
  notok
end

proc{
  iii=5				# dynamic local variable
  $proc = proc{ |i|
    iii = i
  }
  $proc2 = proc {
    $x = iii			# dynamic variables shared by procs
  }
  if defined?(iii)		# dynamic variables' scope
    ok
  else
    notok
  end
}.call
if defined?(iii)		# out of scope
  notok
else
  ok
end
$x=0
$proc.call(5)
$proc2.call
if $x == 5
  ok
else
  notok
end

check "signal"
begin
  kill "SIGINT", $$
  sleep 1
  notok
rescue
  ok
end

$x = 0
trap "SIGINT", proc{|sig| $x = sig;fail}
begin
  kill "SIGINT", $$
  sleep 1
  notok
rescue
  if $x == 2
    ok
  else
    notok
  end
end

$x = FALSE
trap "SIGINT", "$x = TRUE;fail"
begin
  kill "SIGINT", $$
  sleep 1
  notok
rescue
  if $x
    ok
  else
    notok
  end
end

check "eval"
$bad=FALSE
eval 'while FALSE; $bad = TRUE; print "foo\n" end
if not $bad then ok else notok end'

$foo = 'ok'
begin
  eval $foo
rescue
  notok
end

check "system"
if `echo foobar` == "foobar\n"
  ok
else
  notok
end

if `./ruby -e 'print "foobar"'` == 'foobar'
  ok
else
  notok
end

tmp = open("script_tmp", "w")
tmp.print "print $zzz\n";
tmp.close

if `./ruby -s script_tmp -zzz` == 't'
  ok
else
  notok
end

if `./ruby -s script_tmp -zzz=555` == '555'
  ok
else
  notok
end

tmp = open("script_tmp", "w")
tmp.print "#! /usr/local/bin/ruby -s\n";
tmp.print "print $zzz\n";
tmp.close

if `./ruby script_tmp -zzz=678` == '678'
  ok
else
  notok
end

tmp = open("script_tmp", "w")
tmp.print "this is a leading junk\n";
tmp.print "#! /usr/local/bin/ruby -s\n";
tmp.print "print $zzz\n";
tmp.print "__END__\n";
tmp.print "this is a trailing junk\n";
tmp.close

if `./ruby -x script_tmp` == 'nil'
  ok
else
  notok
end

if `./ruby -x script_tmp -zzz=555` == '555'
  ok
else
  notok
end

tmp = open("script_tmp", "w")
for i in 1..5
  tmp.print i, "\n"
end
tmp.close

`./ruby -i.bak -pe 'sub(/^[0-9]+$/){$&.to_i * 5}' script_tmp`
done = TRUE
tmp = open("script_tmp", "r")
while tmp.gets
  if $_.to_i % 5 != 0
    done = FALSE
    notok
    break
  end
end
ok if done
  
File.unlink "script_tmp" or `/bin/rm -f "script_tmp"`
File.unlink "script_tmp.bak" or `/bin/rm -f "script_tmp.bak"`

check "const"
TEST1 = 1
TEST2 = 2

module Const
  TEST3 = 3
  TEST4 = 4
end

module Const2
  TEST3 = 6
  TEST4 = 8
end

include Const

if [TEST1,TEST2,TEST3,TEST4] == [1,2,3,4]
  ok
else
  notok
end

include Const2

if [TEST1,TEST2,TEST3,TEST4] == [1,2,6,8]
  ok
else
  notok
end

check "clone"
foo = Object.new
def foo.test
  "test"
end
bar = foo.clone
def bar.test2
  "test2"
end

if bar.test2 == "test2"
  ok
else
  notok
end
  
if bar.test == "test"
  ok
else
  notok
end
  
if foo.test == "test"
  ok
else
  notok
end

begin
  foo.test2
  notok
rescue
  ok
end

check "pack"

$format = "c2x5CCxsdila6";
# Need the expression in here to force ary[5] to be numeric.  This avoids
# test2 failing because ary2 goes str->numeric->str and ary doesn't.
ary = [1,-100,127,128,32767,987.654321098 / 100.0,12345,123456,"abcdef"]
$x = ary.pack($format)
ary2 = $x.unpack($format)

if ary.length == ary2.length then ok else notok end

if ary.join(':') == ary2.join(':') then ok else notok end

if $x =~ /def/ then ok else notok end

check "math"
if Math.sqrt(4) == 2
  ok
else
  notok
end

include Math
if sqrt(4) == 2
  ok
else
  notok
end

check "struct"
struct_test = Struct.new("Test", :foo, :bar)
if struct_test == Struct::Test
  ok
else
  notok
end
test = struct_test.new(1, 2)
if test.foo == 1 && test.bar == 2
  ok
else
  notok
end
if test[0] == 1 && test[1] == 2
  ok
else
  notok
end
a, b = test
if a == 1 && b == 2
  ok
else
  notok
end
test[0] = 22
if test.foo == 22
  ok
else
  notok
end
test.bar = 47
if test.bar == 47
  ok
else
  notok
end

check "variable"
if $$.is_instance_of? Fixnum
  ok
else
  notok
end

begin
  $$ = 5
  notok
rescue
  ok
end

foobar = "foobar"
$_ = foobar
if $_ == foobar
  ok
else
  notok
end

check "trace"
$x = 1234
$y = 0
trace_var :$x, proc{$y = $x}
$x = 40414
if $y == $x
  ok
else
  notok
end

untrace_var :$x
$x = 19660208
if $y != $x
  ok
else
  notok
end

trace_var :$x, proc{$x *= 2}
$x = 5
if $x == 10
  ok
else
  notok
end
untrace_var :$x

check "defined?"
if defined? $x
  ok
else
  notok
end

foo=5
if defined? foo
  ok
else
  notok
end

if defined? Array
  ok
else
  notok
end

if defined? Object.new
  ok
else
  notok
end

if defined? 1 == 2
  ok
else
  notok
end

if defined? fail
  ok
else
  notok
end
  
def defined_test
  return defined?(yield)
end

if defined_test
  notok
else
  ok
end

if defined_test{}
  ok
else
  notok
end

check "gc"
begin
  1.upto(10000) {
    tmp = [0,1,2,3,4,5,6,7,8,9]
  }
  tmp = nil
  ok
rescue
  notok
end

print "end of test\n" if not $failed
