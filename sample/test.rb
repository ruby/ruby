#! /usr/local/bin/ruby

$testnum=0
$ntest=0
$failed = 0

def check(what)
  printf "%s\n", what
  $what = what
  $testnum = 0
end

def ok(cond)
  $testnum+=1
  $ntest+=1
  if cond
    printf "ok %d\n", $testnum
  else
    where = caller[0]
    printf "not ok %s %d -- %s\n", $what, $testnum, where
    $failed+=1 
  end
end

# make sure conditional operators work

check "condition"

$x = '0';

$x == $x && ok(true)
$x != $x && ok(false)
$x == $x || ok(false)
$x != $x || ok(true)

# first test to see if we can run the tests.

check "if/unless";

$x = 'test';
ok(if $x == $x then true else false end)
$bad = false
unless $x == $x
  $bad = true
end
ok(!$bad)
ok(unless $x != $x then true else false end)

check "case"

case 5
when 1, 2, 3, 4, 6, 7, 8
  ok(false)
when 5
  ok(true)
end

case 5
when 5
  ok(true)
when 1..10
  ok(false)
end

case 5
when 1..10
  ok(true)
else
  ok(false)
end

case 5
when 5
  ok(true)
else
  ok(false)
end

case "foobar"
when /^f.*r$/
  ok(true)
else
  ok(false)
end

check "while/until";

tmp = open("while_tmp", "w")
tmp.print "tvi925\n";
tmp.print "tvi920\n";
tmp.print "vt100\n";
tmp.print "Amiga\n";
tmp.print "paper\n";
tmp.close

# test break

tmp = open("while_tmp", "r")
ok(tmp.kind_of?(File))

while tmp.gets()
  break if /vt100/
end

ok(!tmp.eof? && /vt100/)
tmp.close

# test next
$bad = false
tmp = open("while_tmp", "r")
while tmp.gets()
  next if /vt100/;
  $bad = 1 if /vt100/;
end
ok(!(!tmp.eof? || /vt100/ || $bad))
tmp.close

# test redo
$bad = false
tmp = open("while_tmp", "r")
while tmp.gets()
  if gsub!('vt100', 'VT100')
    gsub!('VT100', 'Vt100')
    redo;
  end
  $bad = 1 if /vt100/;
  $bad = 1 if /VT100/;
end
ok(tmp.eof? && !$bad)
tmp.close

sum=0
for i in 1..10
  sum += i
  i -= 1
  if i > 0
    redo
  end
end
ok(sum == 220)

# test interval
$bad = false
tmp = open("while_tmp", "r")
while tmp.gets()
  break unless 1..2
  if /vt100/ || /Amiga/ || /paper/
    $bad = true
    break
  end
end
ok(!$bad)
tmp.close

File.unlink "while_tmp" or `/bin/rm -f "while_tmp"`
ok(!File.exist?("while_tmp"))

i = 0
until i>4
  i+=1
end
ok(i>4)

# exception handling
check "exception";

begin
  fail "this must be handled"
  ok(false)
rescue
  ok(true)
end

$bad = true
begin
  fail "this must be handled no.2"
rescue
  if $bad
    $bad = false
    retry
    ok(false)
  end
end
ok(true)

# exception in rescue clause
$string = "this must be handled no.3"
begin
  begin
    fail "exception in rescue clause"
  rescue 
    fail $string
  end
  ok(false)
rescue
  ok(true) if $! == $string
end
  
# exception in ensure clause
begin
  begin
    fail "this must be handled no.4"
  ensure 
    fail "exception in ensure clause"
  end
  ok(false)
rescue
  ok(true)
end

$bad = true
begin
  begin
    fail "this must be handled no.5"
  ensure
    $bad = false
  end
rescue
end
ok(!$bad)

$bad = true
begin
  begin
    fail "this must be handled no.6"
  ensure
    $bad = false
  end
rescue
end
ok(!$bad)

$bad = true
while true
  begin
    break
  ensure
    $bad = false
  end
end
ok(!$bad)

ok(catch(:foo) {
     loop do
       loop do
	 throw :foo, true
	 break
       end
       break
       ok(false)			# should no reach here
     end
     false
   })

check "array"
ok([1, 2] + [3, 4] == [1, 2, 3, 4])
ok([1, 2] * 2 == [1, 2, 1, 2])
ok([1, 2] * ":" == "1:2")

ok([1, 2].hash == [1, 2].hash)

ok([1,2,3] & [2,3,4] == [2,3])
ok([1,2,3] | [2,3,4] == [1,2,3,4])
ok([1,2,3] - [2,3] == [1])

$x = [0, 1, 2, 3, 4, 5]
ok($x[2] == 2)
ok($x[1..3] == [1, 2, 3])
ok($x[1,3] == [1, 2, 3])

$x[0, 2] = 10
ok($x[0] == 10 && $x[1] == 2)
  
$x[0, 0] = -1
ok($x[0] == -1 && $x[1] == 10)

$x[-1, 1] = 20
ok($x[-1] == 20 && $x.pop == 20)

# array and/or
ok(([1,2,3]&[2,4,6]) == [2])
ok(([1,2,3]|[2,4,6]) == [1,2,3,4,6])

# compact
$x = [nil, 1, nil, nil, 5, nil, nil]
$x.compact!
ok($x == [1, 5])

# uniq
$x = [1, 1, 4, 2, 5, 4, 5, 1, 2]
$x.uniq!
ok($x == [1, 4, 2, 5])

# empty?
ok(!$x.empty?)
$x = []
ok($x.empty?)

# sort
$x = ["it", "came", "to", "pass", "that", "..."]
$x = $x.sort.join(" ")
ok($x == "... came it pass that to")
$x = [2,5,3,1,7]
$x.sort!{|a,b| a<=>b}		# sort with condition
ok($x == [1,2,3,5,7])
$x.sort!{|a,b| b-a}		# reverse sort
ok($x == [7,5,3,2,1])

# split test
$x = "The Book of Mormon"
ok($x.split(//).reverse!.join == $x.reverse)
ok($x.reverse == $x.reverse!)
ok("1 byte string".split(//).reverse.join(":") == "g:n:i:r:t:s: :e:t:y:b: :1")
$x = "a b c  d"
ok($x.split == ['a', 'b', 'c', 'd'])
ok($x.split(' ') == ['a', 'b', 'c', 'd'])
ok(defined? "a".chomp)
ok("abc".scan(/./) == ["a", "b", "c"])
ok("1a2b3c".scan(/(\d.)/) == [["1a"], ["2b"], ["3c"]])
# non-greedy match
ok("a=12;b=22".scan(/(.*?)=(\d*);?/) == [["a", "12"], ["b", "22"]])

$x = [1]
ok(($x * 5).join(":") == '1:1:1:1:1')
ok(($x * 1).join(":") == '1')
ok(($x * 0).join(":") == '')

*$x = 1..7
ok($x.size == 7)
ok($x == [1, 2, 3, 4, 5, 6, 7])

check "hash"
$x = {1=>2, 2=>4, 3=>6}
$y = {1, 2, 2, 4, 3, 6}

ok($x[1] == 2)

ok(begin   
     for k,v in $y
       fail if k*2 != v
     end
     true
   rescue
     false
   end)

ok($x.length == 3)
ok($x.has_key?(1))
ok($x.has_value?(4))
ok($x.indexes(2,3) == [4,6])
ok($x == {1=>2, 2=>4, 3=>6})

$z = $y.keys.join(":")
ok($z == "1:2:3")

$z = $y.values.join(":")
ok($z == "2:4:6")
ok($x == $y)

$y.shift
ok($y.length == 2)

$z = [1,2]
$y[$z] = 256
ok($y[$z] == 256)

check "iterator"

ok(!iterator?)

def ttt
  ok(iterator?)
end
ttt{}

# yield at top level
ok(!defined?(yield))

$x = [1, 2, 3, 4]
$y = []

# iterator over array
for i in $x
  $y.push i
end
ok($x == $y)

# nested iterator
def tt
  1.upto(10) {|i|
    yield i
  }
end

tt{|i| break if i == 5}
ok(i == 5)

# iterator break/redo/next/retry
unless defined? loop
  def loop
    while true
      yield
    end
  end
  ok(false)
else
  ok(true)
end

done = true
loop{
  break
  done = false
}
ok(done)

done = false
$bad = false
loop {
  break if done
  done = true
  next
  $bad = true
}
ok(!$bad)

done = false
$bad = false
loop {
  break if done
  done = true
  redo
  $bad = true
}
ok(!$bad)

$x = []
for i in 1 .. 7
  $x.push i
end
ok($x.size == 7)
ok($x == [1, 2, 3, 4, 5, 6, 7])

$done = false
$x = []
for i in 1 .. 7			# see how retry works in iterator loop
  if i == 4 and not $done
    $done = true
    retry
  end
  $x.push(i)
end
ok($x.size == 10)
ok($x == [1, 2, 3, 1, 2, 3, 4, 5, 6, 7])

check "bignum"
def fact(n)
  return 1 if n == 0
  f = 1
  while n>0
    f *= n
    n -= 1
  end
  return f
end
fact(3)
$x = fact(40)
ok($x == $x)
ok($x == fact(40))
ok($x < $x+2)
ok($x > $x-2)
ok($x == 815915283247897734345611269596115894272000000000)
ok($x != 815915283247897734345611269596115894272000000001)
ok($x+1 == 815915283247897734345611269596115894272000000001)
ok($x/fact(20) == 335367096786357081410764800000)
$x = -$x
ok($x == -815915283247897734345611269596115894272000000000)
ok(2-(2**32) == -(2**32-2))
ok(2**32 - 5 == (2**32-3)-2)

$good = true;
for i in 1000..1014
  $good = false if ((1<<i) != (2**i))
end
ok($good)

$good = true;
n1=1<<1000
for i in 1000..1014
  $good = false if ((1<<i) != n1)
  n1 *= 2
end
ok($good)

$good = true;
n2=n1
for i in 1..10
  n1 = n1 / 2
  n2 = n2 >> 1
  $good = false if (n1 != n2)
end
ok($good)

$good = true;
for i in 4000..4096
  n1 = 1 << i;
  $good = false if ((n1**2-1) / (n1+1) != (n1-1))
end
ok($good)

check "string & char"

ok("abcd" == "abcd")
ok("abcd" =~ "abcd")
ok("abcd" === "abcd")
ok(("abc" =~ /^$/) == false)
ok(("abc\n" =~ /^$/) == false)
ok(("abc" =~ /^d*$/) == false)
ok(("abc" =~ /d*$/) == 3)
ok("" =~ /^$/)
ok("\n" =~ /^$/)
ok("a\n\n" =~ /^$/)
"abcabc" =~ /.*a/
ok($& == "abca")
"abcabc" =~ /.*c/
ok($& == "abcabc")
"abcabc" =~ /.*?a/
ok($& == "a")
"abcabc" =~ /.*?c/
ok($& == "abc")

$foo = "abc"
ok("#$foo = abc" == "abc = abc")
ok("#{$foo} = abc" == "abc = abc")

foo = "abc"
ok("#{foo} = abc" == "abc = abc")

ok('-' * 5 == '-----')
ok('-' * 1 == '-')
ok('-' * 0 == '')

foo = '-'
ok(foo * 5 == '-----')
ok(foo * 1 == '-')
ok(foo * 0 == '')

$x = "a.gif"
ok($x.sub(/.*\.([^\.]+)$/, '\1') == "gif")
ok($x.sub(/.*\.([^\.]+)$/, 'b.\1') == "b.gif")
ok($x.sub(/.*\.([^\.]+)$/, '\2') == "")
ok($x.sub(/.*\.([^\.]+)$/, 'a\2b') == "ab")
ok($x.sub(/.*\.([^\.]+)$/, '<\&>') == "<a.gif>")

# character constants(assumes ASCII)
ok("a"[0] == ?a)
ok(?a == ?a)
ok(?\C-a == 1)
ok(?\M-a == 225)
ok(?\M-\C-a == 129)
ok("a".upcase![0] == ?A)
ok("A".downcase![0] == ?a)
ok("abc".tr!("a-z", "A-Z") == "ABC")
ok("aabbcccc".tr_s!("a-z", "A-Z") == "ABC")
ok("abc".tr!("0-9", "A-Z") == nil)
ok("abcc".squeeze!("a-z") == "abc")
ok("abcd".delete!("bc") == "ad")

$x = "abcdef"
$y = [ ?a, ?b, ?c, ?d, ?e, ?f ]
$bad = false
$x.each_byte {|i|
  if i != $y.shift
    $bad = true
    break
  end
}
ok(!$bad)

check "asignment"
a = nil
ok(defined?(a))
ok(a == nil)

# multiple asignment
a, b = 1, 2
ok(a == 1 && b == 2)

a, b = b, a
ok(a == 2 && b == 1)

a, = 1,2
ok(a == 1)

a, *b = 1, 2, 3
ok(a == 1 && b == [2, 3])

*a = 1, 2, 3
ok(a == [1, 2, 3])

*a = 1..3
ok(a == [1, 2, 3])

check "call"
def aaa(a, b=100, *rest)
  res = [a, b]
  res += rest if rest
  return res
end

# not enough argument
begin
  aaa()				# need at least 1 arg
  ok(false)
rescue
  ok(true)
end

begin
  aaa				# no arg given (exception raised)
  ok(false)
rescue
  ok(true)
end

ok(aaa(1) == [1, 100])
ok(aaa(1, 2) == [1, 2])
ok(aaa(1, 2, 3, 4) == [1, 2, 3, 4])
ok(aaa(1, *[2, 3, 4]) == [1, 2, 3, 4])

check "proc"
$proc = proc{|i| i}
ok($proc.call(2) == 2)
ok($proc.call(3) == 3)

$proc = proc{|i| i*2}
ok($proc.call(2) == 4)
ok($proc.call(3) == 6)

proc{
  iii=5				# nested local variable
  $proc = proc{|i|
    iii = i
  }
  $proc2 = proc {
    $x = iii			# nested variables shared by procs
  }
  # scope of nested variables
  ok(defined?(iii))
}.call
ok(!defined?(iii))		# out of scope

$x=0
$proc.call(5)
$proc2.call
p $x
ok($x == 5)

if defined? Process.kill
  check "signal"

  $x = 0
  trap "SIGINT", proc{|sig| $x = 2}
  Process.kill "SIGINT", $$
  sleep 0.1
  ok($x == 2)

  trap "SIGINT", proc{fail "Interrupt"}

  x = false
  begin
    Process.kill "SIGINT", $$
    sleep 0.1
  rescue
    x = $!
  end
  ok(x && x =~ /Interrupt/)
end

check "eval"
ok(eval("") == nil)
$bad=false
eval 'while false; $bad = true; print "foo\n" end'
ok(!$bad)

ok(eval('TRUE'))
ok(eval('true'))
ok(!eval('NIL'))
ok(!eval('nil'))
ok(!eval('FALSE'))
ok(!eval('false'))

$foo = 'ok(true)'
begin
  eval $foo
rescue
  ok(false)
end

ok(eval("$foo") == 'ok(true)')
ok(eval("true") == true)
i = 5
ok(eval("i == 5"))
ok(eval("i") == 5)
ok(eval("defined? i"))

# eval with binding
def test_ev
  local1 = "local1"
  lambda {
    local2 = "local2"
    return binding
  }.call
end

$x = test_ev
ok(eval("local1", $x) == "local1") # normal local var
ok(eval("local2", $x) == "local2") # nested local var
$bad = true
begin
  p eval("local1")
rescue NameError		# must raise error
  $bad = false
end
ok(!$bad)

module EvTest
  EVTEST1 = 25
  evtest2 = 125
  $x = binding
end
ok(eval("EVTEST1", $x) == 25)	# constant in module
ok(eval("evtest2", $x) == 125)	# local var in module
$bad = true
begin
  eval("EVTEST1")
rescue NameError		# must raise error
  $bad = false
end
ok(!$bad)

check "system"
ok(`echo foobar` == "foobar\n")
ok(`./ruby -e 'print "foobar"'` == 'foobar')

tmp = open("script_tmp", "w")
tmp.print "print $zzz\n";
tmp.close

ok(`./ruby -s script_tmp -zzz` == 'true')
ok(`./ruby -s script_tmp -zzz=555` == '555')

tmp = open("script_tmp", "w")
tmp.print "#! /usr/local/bin/ruby -s\n";
tmp.print "print $zzz\n";
tmp.close

ok(`./ruby script_tmp -zzz=678` == '678')

tmp = open("script_tmp", "w")
tmp.print "this is a leading junk\n";
tmp.print "#! /usr/local/bin/ruby -s\n";
tmp.print "print $zzz\n";
tmp.print "__END__\n";
tmp.print "this is a trailing junk\n";
tmp.close

ok(`./ruby -x script_tmp` == 'nil')
ok(`./ruby -x script_tmp -zzz=555` == '555')

tmp = open("script_tmp", "w")
for i in 1..5
  tmp.print i, "\n"
end
tmp.close

`./ruby -i.bak -pe 'sub(/^[0-9]+$/){$&.to_i * 5}' script_tmp`
done = true
tmp = open("script_tmp", "r")
while tmp.gets
  if $_.to_i % 5 != 0
    done = false
    break
  end
end
tmp.close
ok(done)
  
File.unlink "script_tmp" or `/bin/rm -f "script_tmp"`
File.unlink "script_tmp.bak" or `/bin/rm -f "script_tmp.bak"`

$bad = false
for script in Dir["{lib,sample}/*.rb"]
  unless `./ruby -c #{script}` == "Syntax OK\n"
    $bad = true
  end
end
ok(!$bad)

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

ok([TEST1,TEST2,TEST3,TEST4] == [1,2,3,4])

include Const2
STDERR.print "intentionally redefines TEST3, TEST4\n" if $VERBOSE
ok([TEST1,TEST2,TEST3,TEST4] == [1,2,6,8])

check "clone"
foo = Object.new
def foo.test
  "test"
end
bar = foo.clone
def bar.test2
  "test2"
end

ok(bar.test2 == "test2")
ok(bar.test == "test")
ok(foo.test == "test")  

begin
  foo.test2
  ok false
rescue
  ok true
end

check "pack"

$format = "c2x5CCxsdila6";
# Need the expression in here to force ary[5] to be numeric.  This avoids
# test2 failing because ary2 goes str->numeric->str and ary does not.
ary = [1,-100,127,128,32767,987.654321098 / 100.0,12345,123456,"abcdef"]
$x = ary.pack($format)
ary2 = $x.unpack($format)

ok(ary.length == ary2.length)
ok(ary.join(':') == ary2.join(':'))
ok($x =~ /def/)

check "math"
ok(Math.sqrt(4) == 2)

include Math
ok(sqrt(4) == 2)

check "struct"
struct_test = Struct.new("Test", :foo, :bar)
ok(struct_test == Struct::Test)

test = struct_test.new(1, 2)
ok(test.foo == 1 && test.bar == 2)
ok(test[0] == 1 && test[1] == 2)

a, b = test
ok(a == 1 && b == 2)

test[0] = 22
ok(test.foo == 22)

test.bar = 47
ok(test.bar == 47)

check "variable"
ok($$.instance_of?(Fixnum))

# read-only variable
begin
  $$ = 5
  ok false
rescue
  ok true
end

foobar = "foobar"
$_ = foobar
ok($_ == foobar)

check "trace"
$x = 1234
$y = 0
trace_var :$x, proc{$y = $x}
$x = 40414
ok($y == $x)

untrace_var :$x
$x = 19660208
ok($y != $x)

trace_var :$x, proc{$x *= 2}
$x = 5
ok($x == 10)

untrace_var :$x

check "defined?"

ok(defined?($x))		# global variable
ok(defined?($x) == 'global-variable')# returns description

foo=5
ok(defined?(foo))		# local variable

ok(defined?(Array))		# constant
ok(defined?(Object.new))	# method
ok(!defined?(Object.print))	# private method
ok(defined?(1 == 2))		# operator expression

def defined_test
  return !defined?(yield)
end

ok(defined_test)		# not iterator
ok(!defined_test{})		# called as iterator

check "alias"
class Alias0
  def foo; "foo" end
end
class Alias1<Alias0
  alias bar foo
  def foo; "foo+" + super end
end
class Alias2<Alias1
  alias baz foo
  undef foo
end

x = Alias2.new
ok(x.bar == "foo")
ok(x.baz == "foo+foo")

# check for cache
ok(x.baz == "foo+foo")

class Alias3<Alias2
  def foo
    defined? super
  end
  def bar
    defined? super
  end
  def quux
    defined? super
  end
end
x = Alias3.new
ok(!x.foo)
ok(x.bar)
ok(!x.quux)

check "gc"
begin
  1.upto(10000) {
    tmp = [0,1,2,3,4,5,6,7,8,9]
  }
  tmp = nil
  ok true
rescue
  ok false
end

if $failed > 0
  printf "test: %d failed %d\n", $ntest, $failed
else
  printf "end of test(test: %d)\n", $ntest
end
