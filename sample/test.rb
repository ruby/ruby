#! /usr/bin/env ruby

$testnum=0
$ntest=0
$failed = 0

def test_check(what)
  printf "%s\n", what
  $what = what
  $testnum = 0
end

def test_ok(cond)
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

test_check "assignment"

a=[]; a[0] ||= "bar";
test_ok(a[0] == "bar")
h={}; h["foo"] ||= "bar";
test_ok(h["foo"] == "bar")

aa = 5
aa ||= 25
test_ok(aa == 5)
bb ||= 25
test_ok(bb == 25)
cc &&=33
test_ok(cc == nil)
cc = 5
cc &&=44
test_ok(cc == 44)

test_check "condition"

$x = '0';

$x == $x && test_ok(true)
$x != $x && test_ok(false)
$x == $x || test_ok(false)
$x != $x || test_ok(true)

# first test to see if we can run the tests.

test_check "if/unless";

$x = 'test';
test_ok(if $x == $x then true else false end)
$bad = false
unless $x == $x
  $bad = true
end
test_ok(!$bad)
test_ok(unless $x != $x then true else false end)

test_check "case"

case 5
when 1, 2, 3, 4, 6, 7, 8
  test_ok(false)
when 5
  test_ok(true)
end

case 5
when 5
  test_ok(true)
when 1..10
  test_ok(false)
end

case 5
when 1..10
  test_ok(true)
else
  test_ok(false)
end

case 5
when 5
  test_ok(true)
else
  test_ok(false)
end

case "foobar"
when /^f.*r$/
  test_ok(true)
else
  test_ok(false)
end

test_check "while/until";

tmp = open("while_tmp", "w")
tmp.print "tvi925\n";
tmp.print "tvi920\n";
tmp.print "vt100\n";
tmp.print "Amiga\n";
tmp.print "paper\n";
tmp.close

# test break

tmp = open("while_tmp", "r")
test_ok(tmp.kind_of?(File))

while tmp.gets()
  break if /vt100/
end

test_ok(!tmp.eof? && /vt100/)
tmp.close

# test next
$bad = false
tmp = open("while_tmp", "r")
while tmp.gets()
  next if /vt100/;
  $bad = 1 if /vt100/;
end
test_ok(!(!tmp.eof? || /vt100/ || $bad))
tmp.close

# test redo
$bad = false
tmp = open("while_tmp", "r")
while tmp.gets()
  line = $_
  $_ = gsub(/vt100/, 'VT100')
  if $_ != line
    gsub!('VT100', 'Vt100')
    redo;
  end
  $bad = 1 if /vt100/
  $bad = 1 if /VT100/
end
test_ok(tmp.eof? && !$bad)
tmp.close

sum=0
for i in 1..10
  sum += i
  i -= 1
  if i > 0
    redo
  end
end
test_ok(sum == 220)

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
test_ok(!$bad)
tmp.close

File.unlink "while_tmp" or `/bin/rm -f "while_tmp"`
test_ok(!File.exist?("while_tmp"))

i = 0
until i>4
  i+=1
end
test_ok(i>4)


# exception handling
test_check "exception";

begin
  raise "this must be handled"
  test_ok(false)
rescue
  test_ok(true)
end

$bad = true
begin
  raise "this must be handled no.2"
rescue
  if $bad
    $bad = false
    retry
    test_ok(false)
  end
end
test_ok(true)

# exception in rescue clause
$string = "this must be handled no.3"
begin
  begin
    raise "exception in rescue clause"
  rescue 
    raise $string
  end
  test_ok(false)
rescue
  test_ok(true) if $! == $string
end
  
# exception in ensure clause
begin
  begin
    raise "this must be handled no.4"
  ensure 
    raise "exception in ensure clause"
  end
  test_ok(false)
rescue
  test_ok(true)
end

$bad = true
begin
  begin
    raise "this must be handled no.5"
  ensure
    $bad = false
  end
rescue
end
test_ok(!$bad)

$bad = true
begin
  begin
    raise "this must be handled no.6"
  ensure
    $bad = false
  end
rescue
end
test_ok(!$bad)

$bad = true
while true
  begin
    break
  ensure
    $bad = false
  end
end
test_ok(!$bad)

test_ok(catch(:foo) {
     loop do
       loop do
	 throw :foo, true
	 break
       end
       break
       test_ok(false)			# should no reach here
     end
     false
   })

test_check "array"
test_ok([1, 2] + [3, 4] == [1, 2, 3, 4])
test_ok([1, 2] * 2 == [1, 2, 1, 2])
test_ok([1, 2] * ":" == "1:2")

test_ok([1, 2].hash == [1, 2].hash)

test_ok([1,2,3] & [2,3,4] == [2,3])
test_ok([1,2,3] | [2,3,4] == [1,2,3,4])
test_ok([1,2,3] - [2,3] == [1])

$x = [0, 1, 2, 3, 4, 5]
test_ok($x[2] == 2)
test_ok($x[1..3] == [1, 2, 3])
test_ok($x[1,3] == [1, 2, 3])

$x[0, 2] = 10
test_ok($x[0] == 10 && $x[1] == 2)
  
$x[0, 0] = -1
test_ok($x[0] == -1 && $x[1] == 10)

$x[-1, 1] = 20
test_ok($x[-1] == 20 && $x.pop == 20)

# array and/or
test_ok(([1,2,3]&[2,4,6]) == [2])
test_ok(([1,2,3]|[2,4,6]) == [1,2,3,4,6])

# compact
$x = [nil, 1, nil, nil, 5, nil, nil]
$x.compact!
test_ok($x == [1, 5])

# uniq
$x = [1, 1, 4, 2, 5, 4, 5, 1, 2]
$x.uniq!
test_ok($x == [1, 4, 2, 5])

# empty?
test_ok(!$x.empty?)
$x = []
test_ok($x.empty?)

# sort
$x = ["it", "came", "to", "pass", "that", "..."]
$x = $x.sort.join(" ")
test_ok($x == "... came it pass that to")
$x = [2,5,3,1,7]
$x.sort!{|a,b| a<=>b}		# sort with condition
test_ok($x == [1,2,3,5,7])
$x.sort!{|a,b| b-a}		# reverse sort
test_ok($x == [7,5,3,2,1])

# split test
$x = "The Botest_ok of Mormon"
test_ok($x.split(//).reverse!.join == $x.reverse)
test_ok($x.reverse == $x.reverse!)
test_ok("1 byte string".split(//).reverse.join(":") == "g:n:i:r:t:s: :e:t:y:b: :1")
$x = "a b c  d"
test_ok($x.split == ['a', 'b', 'c', 'd'])
test_ok($x.split(' ') == ['a', 'b', 'c', 'd'])
test_ok(defined? "a".chomp)
test_ok("abc".scan(/./) == ["a", "b", "c"])
test_ok("1a2b3c".scan(/(\d.)/) == [["1a"], ["2b"], ["3c"]])
# non-greedy match
test_ok("a=12;b=22".scan(/(.*?)=(\d*);?/) == [["a", "12"], ["b", "22"]])

$x = [1]
test_ok(($x * 5).join(":") == '1:1:1:1:1')
test_ok(($x * 1).join(":") == '1')
test_ok(($x * 0).join(":") == '')

*$x = (1..7).to_a
test_ok($x.size == 7)
test_ok($x == [1, 2, 3, 4, 5, 6, 7])

test_check "hash"
$x = {1=>2, 2=>4, 3=>6}
$y = {1, 2, 2, 4, 3, 6}

test_ok($x[1] == 2)

test_ok(begin   
     for k,v in $y
       raise if k*2 != v
     end
     true
   rescue
     false
   end)

test_ok($x.length == 3)
test_ok($x.has_key?(1))
test_ok($x.has_value?(4))
test_ok($x.indexes(2,3) == [4,6])
test_ok($x == {1=>2, 2=>4, 3=>6})

$z = $y.keys.join(":")
test_ok($z == "1:2:3")

$z = $y.values.join(":")
test_ok($z == "2:4:6")
test_ok($x == $y)

$y.shift
test_ok($y.length == 2)

$z = [1,2]
$y[$z] = 256
test_ok($y[$z] == 256)

$x = [1,2,3]
$x[1,0] = $x
test_ok($x == [1,1,2,3,2,3])

$x = [1,2,3]
$x[-1,0] = $x
test_ok($x == [1,2,1,2,3,3])

$x = [1,2,3]
$x.concat($x)
test_ok($x == [1,2,3,1,2,3])

test_check "iterator"

test_ok(!iterator?)

def ttt
  test_ok(iterator?)
end
ttt{}

# yield at top level
test_ok(!defined?(yield))

$x = [1, 2, 3, 4]
$y = []

# iterator over array
for i in $x
  $y.push i
end
test_ok($x == $y)

# nested iterator
def tt
  1.upto(10) {|i|
    yield i
  }
end

tt{|i| break if i == 5}
test_ok(i == 5)

def tt2(dummy)
  yield 1
end

def tt3(&block)
  tt2(raise(ArgumentError,""),&block)
end

$x = false
begin
  tt3{}
rescue ArgumentError
  $x = true
rescue Exception
end
test_ok($x)

# iterator break/redo/next/retry
done = true
loop{
  break
  done = false			# should not reach here
}
test_ok(done)

done = false
$bad = false
loop {
  break if done
  done = true
  next
  $bad = true			# should not reach here
}
test_ok(!$bad)

done = false
$bad = false
loop {
  break if done
  done = true
  redo
  $bad = true			# should not reach here
}
test_ok(!$bad)

$x = []
for i in 1 .. 7
  $x.push i
end
test_ok($x.size == 7)
test_ok($x == [1, 2, 3, 4, 5, 6, 7])

$done = false
$x = []
for i in 1 .. 7			# see how retry works in iterator loop
  if i == 4 and not $done
    $done = true
    retry
  end
  $x.push(i)
end
test_ok($x.size == 10)
test_ok($x == [1, 2, 3, 1, 2, 3, 4, 5, 6, 7])

# append method to built-in class
class Array
  def iter_test1
    collect{|e| [e, yield(e)]}.sort{|a,b|a[1]<=>b[1]}
  end
  def iter_test2
    a = collect{|e| [e, yield(e)]}
    a.sort{|a,b|a[1]<=>b[1]}
  end
end
$x = [[1,2],[3,4],[5,6]]
test_ok($x.iter_test1{|x|x} == $x.iter_test2{|x|x})

class IterTest
  def initialize(e); @body = e; end

  def each0(&block); @body.each(&block); end
  def each1(&block); @body.each { |*x| block.call(*x) } end
  def each2(&block); @body.each { |*x| block.call(x) } end
  def each3(&block); @body.each { |x| block.call(*x) } end
  def each4(&block); @body.each { |x| block.call(x) } end
  def each5; @body.each { |*x| yield(*x) } end
  def each6; @body.each { |*x| yield(x) } end
  def each7; @body.each { |x| yield(*x) } end
  def each8; @body.each { |x| yield(x) } end
end

IterTest.new([0]).each0 { |x| $x = x }
test_ok($x == 0)
IterTest.new([1]).each1 { |x| $x = x }
test_ok($x == 1)
IterTest.new([2]).each2 { |x| $x = x }
test_ok($x == [2])
IterTest.new([3]).each3 { |x| $x = x }
test_ok($x == 3)
IterTest.new([4]).each4 { |x| $x = x }
test_ok($x == 4)
IterTest.new([5]).each5 { |x| $x = x }
test_ok($x == 5)
IterTest.new([6]).each6 { |x| $x = x }
test_ok($x == [6])
IterTest.new([7]).each7 { |x| $x = x }
test_ok($x == 7)
IterTest.new([8]).each8 { |x| $x = x }
test_ok($x == 8)

IterTest.new([[0]]).each0 { |x| $x = x }
test_ok($x == [0])
IterTest.new([[1]]).each1 { |x| $x = x }
test_ok($x == 1)
IterTest.new([[2]]).each2 { |x| $x = x }
test_ok($x == [2])
IterTest.new([[3]]).each3 { |x| $x = x }
test_ok($x == 3)
IterTest.new([[4]]).each4 { |x| $x = x }
test_ok($x == [4])
IterTest.new([[5]]).each5 { |x| $x = x }
test_ok($x == 5)
IterTest.new([[6]]).each6 { |x| $x = x }
test_ok($x == [6])
IterTest.new([[7]]).each7 { |x| $x = x }
test_ok($x == 7)
IterTest.new([[8]]).each8 { |x| $x = x }
test_ok($x == [8])

IterTest.new([[0,0]]).each0 { |x| $x = x }
test_ok($x == [0,0])
IterTest.new([[8,8]]).each8 { |x| $x = x }
test_ok($x == [8,8])

test_check "float"
test_ok(2.6.floor == 2)
test_ok(-2.6.floor == -3)
test_ok(2.6.ceil == 3)
test_ok(-2.6.ceil == -2)
test_ok(2.6.truncate == 2)
test_ok(-2.6.truncate == -2)
test_ok(2.6.round == 3)
test_ok(-2.4.truncate == -2)
test_ok((13.4 % 1 - 0.4).abs < 0.0001)

test_check "bignum"
def fact(n)
  return 1 if n == 0
  f = 1
  while n>0
    f *= n
    n -= 1
  end
  return f
end
$x = fact(40)
test_ok($x == $x)
test_ok($x == fact(40))
test_ok($x < $x+2)
test_ok($x > $x-2)
test_ok($x == 815915283247897734345611269596115894272000000000)
test_ok($x != 815915283247897734345611269596115894272000000001)
test_ok($x+1 == 815915283247897734345611269596115894272000000001)
test_ok($x/fact(20) == 335367096786357081410764800000)
$x = -$x
test_ok($x == -815915283247897734345611269596115894272000000000)
test_ok(2-(2**32) == -(2**32-2))
test_ok(2**32 - 5 == (2**32-3)-2)

$good = true;
for i in 1000..1014
  $good = false if ((1<<i) != (2**i))
end
test_ok($good)

$good = true;
n1=1<<1000
for i in 1000..1014
  $good = false if ((1<<i) != n1)
  n1 *= 2
end
test_ok($good)

$good = true;
n2=n1
for i in 1..10
  n1 = n1 / 2
  n2 = n2 >> 1
  $good = false if (n1 != n2)
end
test_ok($good)

$good = true;
for i in 4000..4096
  n1 = 1 << i;
  if (n1**2-1) / (n1+1) != (n1-1)
    p i
    $good = false
  end
end
test_ok($good)

b = 10**80
a = b * 9 + 7
test_ok(7 == a.modulo(b))
test_ok(-b + 7 == a.modulo(-b))
test_ok(b + -7 == (-a).modulo(b))
test_ok(-7 == (-a).modulo(-b))
test_ok(7 == a.remainder(b))
test_ok(7 == a.remainder(-b))
test_ok(-7 == (-a).remainder(b))
test_ok(-7 == (-a).remainder(-b))

test_ok(10**40+10**20 == 10000000000000000000100000000000000000000)
test_ok(10**40/10**20 == 100000000000000000000)

test_check "string & char"

test_ok("abcd" == "abcd")
test_ok("abcd" =~ "abcd")
test_ok("abcd" === "abcd")
# compile time string concatenation
test_ok("ab" "cd" == "abcd")
test_ok("#{22}aa" "cd#{44}" == "22aacd44")
test_ok("#{22}aa" "cd#{44}" "55" "#{66}" == "22aacd445566")
test_ok("abc" !~ /^$/)
test_ok("abc\n" !~ /^$/)
test_ok("abc" !~ /^d*$/)
test_ok(("abc" =~ /d*$/) == 3)
test_ok("" =~ /^$/)
test_ok("\n" =~ /^$/)
test_ok("a\n\n" =~ /^$/)
test_ok("abcabc" =~ /.*a/ && $& == "abca")
test_ok("abcabc" =~ /.*c/ && $& == "abcabc")
test_ok("abcabc" =~ /.*?a/ && $& == "a")
test_ok("abcabc" =~ /.*?c/ && $& == "abc")
test_ok(/(.|\n)*?\n(b|\n)/ =~ "a\nb\n\n" && $& == "a\nb")

test_ok(/^(ab+)+b/ =~ "ababb" && $& == "ababb")
test_ok(/^(?:ab+)+b/ =~ "ababb" && $& == "ababb")
test_ok(/^(ab+)+/ =~ "ababb" && $& == "ababb")
test_ok(/^(?:ab+)+/ =~ "ababb" && $& == "ababb")

test_ok(/(\s+\d+){2}/ =~ " 1 2" && $& == " 1 2")
test_ok(/(?:\s+\d+){2}/ =~ " 1 2" && $& == " 1 2")

$x = <<END;
ABCD
ABCD
END
$x.gsub!(/((.|\n)*?)B((.|\n)*?)D/){$1+$3}
test_ok($x == "AC\nAC\n")

test_ok("foobar" =~ /foo(?=(bar)|(baz))/)
test_ok("foobaz" =~ /foo(?=(bar)|(baz))/)

$foo = "abc"
test_ok("#$foo = abc" == "abc = abc")
test_ok("#{$foo} = abc" == "abc = abc")

foo = "abc"
test_ok("#{foo} = abc" == "abc = abc")

test_ok('-' * 5 == '-----')
test_ok('-' * 1 == '-')
test_ok('-' * 0 == '')

foo = '-'
test_ok(foo * 5 == '-----')
test_ok(foo * 1 == '-')
test_ok(foo * 0 == '')

$x = "a.gif"
test_ok($x.sub(/.*\.([^\.]+)$/, '\1') == "gif")
test_ok($x.sub(/.*\.([^\.]+)$/, 'b.\1') == "b.gif")
test_ok($x.sub(/.*\.([^\.]+)$/, '\2') == "")
test_ok($x.sub(/.*\.([^\.]+)$/, 'a\2b') == "ab")
test_ok($x.sub(/.*\.([^\.]+)$/, '<\&>') == "<a.gif>")

# character constants(assumes ASCII)
test_ok("a"[0] == ?a)
test_ok(?a == ?a)
test_ok(?\C-a == 1)
test_ok(?\M-a == 225)
test_ok(?\M-\C-a == 129)
test_ok("a".upcase![0] == ?A)
test_ok("A".downcase![0] == ?a)
test_ok("abc".tr!("a-z", "A-Z") == "ABC")
test_ok("aabbcccc".tr_s!("a-z", "A-Z") == "ABC")
test_ok("abcc".squeeze!("a-z") == "abc")
test_ok("abcd".delete!("bc") == "ad")

$x = "abcdef"
$y = [ ?a, ?b, ?c, ?d, ?e, ?f ]
$bad = false
$x.each_byte {|i|
  if i != $y.shift
    $bad = true
    break
  end
}
test_ok(!$bad)

s = "a string"
s[0..s.size]="another string"
test_ok(s == "another string")

test_check "assignment"
a = nil
test_ok(defined?(a))
test_ok(a == nil)

# multiple asignment
a, b = 1, 2
test_ok(a == 1 && b == 2)

a, b = b, a
test_ok(a == 2 && b == 1)

a, = 1,2
test_ok(a == 1)

a, *b = 1, 2, 3
test_ok(a == 1 && b == [2, 3])

a, (b, c), d = 1, [2, 3], 4
test_ok(a == 1 && b == 2 && c == 3 && d == 4)

*a = 1, 2, 3
test_ok(a == [1, 2, 3])

*a = 4
test_ok(a == [4])

*a = nil
test_ok(a == [nil])

test_check "call"
def aaa(a, b=100, *rest)
  res = [a, b]
  res += rest if rest
  return res
end

# not enough argument
begin
  aaa()				# need at least 1 arg
  test_ok(false)
rescue
  test_ok(true)
end

begin
  aaa				# no arg given (exception raised)
  test_ok(false)
rescue
  test_ok(true)
end

test_ok(aaa(1) == [1, 100])
test_ok(aaa(1, 2) == [1, 2])
test_ok(aaa(1, 2, 3, 4) == [1, 2, 3, 4])
test_ok(aaa(1, *[2, 3, 4]) == [1, 2, 3, 4])

test_check "proc"
$proc = proc{|i| i}
test_ok($proc.call(2) == 2)
test_ok($proc.call(3) == 3)

$proc = proc{|i| i*2}
test_ok($proc.call(2) == 4)
test_ok($proc.call(3) == 6)

proc{
  iii=5				# nested local variable
  $proc = proc{|i|
    iii = i
  }
  $proc2 = proc {
    $x = iii			# nested variables shared by procs
  }
  # scope of nested variables
  test_ok(defined?(iii))
}.call
test_ok(!defined?(iii))		# out of scope

$x=0
$proc.call(5)
$proc2.call
test_ok($x == 5)

if defined? Process.kill
  test_check "signal"

  $x = 0
  trap "SIGINT", proc{|sig| $x = 2}
  Process.kill "SIGINT", $$
  sleep 0.1
  test_ok($x == 2)

  trap "SIGINT", proc{raise "Interrupt"}

  x = false
  begin
    Process.kill "SIGINT", $$
    sleep 0.1
  rescue
    x = $!
  end
  test_ok(x && /Interrupt/ =~ x)
end

test_check "eval"
test_ok(eval("") == nil)
$bad=false
eval 'while false; $bad = true; print "foo\n" end'
test_ok(!$bad)

test_ok(eval('TRUE'))
test_ok(eval('true'))
test_ok(!eval('NIL'))
test_ok(!eval('nil'))
test_ok(!eval('FALSE'))
test_ok(!eval('false'))

$foo = 'test_ok(true)'
begin
  eval $foo
rescue
  test_ok(false)
end

test_ok(eval("$foo") == 'test_ok(true)')
test_ok(eval("true") == true)
i = 5
test_ok(eval("i == 5"))
test_ok(eval("i") == 5)
test_ok(eval("defined? i"))

# eval with binding
def test_ev
  local1 = "local1"
  lambda {
    local2 = "local2"
    return binding
  }.call
end

$x = test_ev
test_ok(eval("local1", $x) == "local1") # normal local var
test_ok(eval("local2", $x) == "local2") # nested local var
$bad = true
begin
  p eval("local1")
rescue NameError		# must raise error
  $bad = false
end
test_ok(!$bad)

module EvTest
  EVTEST1 = 25
  evtest2 = 125
  $x = binding
end
test_ok(eval("EVTEST1", $x) == 25)	# constant in module
test_ok(eval("evtest2", $x) == 125)	# local var in module
$bad = true
begin
  eval("EVTEST1")
rescue NameError		# must raise error
  $bad = false
end
test_ok(!$bad)

x = proc{}
eval "i4 = 1", x
test_ok(eval("i4", x) == 1)
x = proc{proc{}}.call
eval "i4 = 22", x
test_ok(eval("i4", x) == 22)
$x = []
x = proc{proc{}}.call
eval "(0..9).each{|i5| $x[i5] = proc{i5*2}}", x
test_ok($x[4].call == 8)

x = binding
eval "i = 1", x
test_ok(eval("i", x) == 1)
x = proc{binding}.call
eval "i = 22", x
test_ok(eval("i", x) == 22)
$x = []
x = proc{binding}.call
eval "(0..9).each{|i5| $x[i5] = proc{i5*2}}", x
test_ok($x[4].call == 8)
x = proc{binding}.call
eval "for i6 in 1..1; j6=i6; end", x
test_ok(eval("defined? i6", x))
test_ok(eval("defined? j6", x))

proc {
  p = binding
  eval "foo11 = 1", p
  foo22 = 5
  proc{foo11=22}.call
  proc{foo22=55}.call
  test_ok(eval("foo11", p) == eval("foo11"))
  test_ok(eval("foo11") == 1)
  test_ok(eval("foo22", p) == eval("foo22"))
  test_ok(eval("foo22") == 55)
}.call

p1 = proc{i7 = 0; proc{i7}}.call
test_ok(p1.call == 0)
eval "i7=5", p1
test_ok(p1.call == 5)
test_ok(!defined?(i7))

p1 = proc{i7 = 0; proc{i7}}.call
i7 = nil
test_ok(p1.call == 0)
eval "i7=1", p1
test_ok(p1.call == 1)
eval "i7=5", p1
test_ok(p1.call == 5)
test_ok(i7 == nil)

test_check "system"
test_ok(`echo foobar` == "foobar\n")
test_ok(`./miniruby -e 'print "foobar"'` == 'foobar')

tmp = open("script_tmp", "w")
tmp.print "print $zzz\n";
tmp.close

test_ok(`./miniruby -s script_tmp -zzz` == 'true')
test_ok(`./miniruby -s script_tmp -zzz=555` == '555')

tmp = open("script_tmp", "w")
tmp.print "#! /usr/local/bin/ruby -s\n";
tmp.print "print $zzz\n";
tmp.close

test_ok(`./miniruby script_tmp -zzz=678` == '678')

tmp = open("script_tmp", "w")
tmp.print "this is a leading junk\n";
tmp.print "#! /usr/local/bin/ruby -s\n";
tmp.print "print $zzz\n";
tmp.print "__END__\n";
tmp.print "this is a trailing junk\n";
tmp.close

test_ok(`./miniruby -x script_tmp` == 'nil')
test_ok(`./miniruby -x script_tmp -zzz=555` == '555')

tmp = open("script_tmp", "w")
for i in 1..5
  tmp.print i, "\n"
end
tmp.close

`./miniruby -i.bak -pe 'sub(/^[0-9]+$/){$&.to_i * 5}' script_tmp`
done = true
tmp = open("script_tmp", "r")
while tmp.gets
  if $_.to_i % 5 != 0
    done = false
    break
  end
end
tmp.close
test_ok(done)
  
File.unlink "script_tmp" or `/bin/rm -f "script_tmp"`
File.unlink "script_tmp.bak" or `/bin/rm -f "script_tmp.bak"`

$bad = false
if (dir = File.dirname(File.dirname($0))) == '.'
  dir = ""
else
  dir << "/"
end
for script in Dir["#{dir}{lib,sample,ext}/**/*.rb"]
  `./miniruby -c #{script}`
  unless $?
    $bad = true
  end
end
test_ok(!$bad)

test_check "const"
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

test_ok([TEST1,TEST2,TEST3,TEST4] == [1,2,3,4])

include Const2
STDERR.print "intentionally redefines TEST3, TEST4\n" if $VERBOSE
test_ok([TEST1,TEST2,TEST3,TEST4] == [1,2,6,8])

test_check "clone"
foo = Object.new
def foo.test
  "test"
end
bar = foo.clone
def bar.test2
  "test2"
end

test_ok(bar.test2 == "test2")
test_ok(bar.test == "test")
test_ok(foo.test == "test")  

begin
  foo.test2
  test_ok false
rescue NameError
  test_ok true
end

test_check "marshal"
$x = [1,2,3,[4,5,"foo"],{1=>"bar"},2.5,fact(30)]
$y = Marshal.dump($x)
test_ok($x == Marshal.load($y))

test_check "pack"

$format = "c2x5CCxsdils_l_a6";
# Need the expression in here to force ary[5] to be numeric.  This avoids
# test2 failing because ary2 goes str->numeric->str and ary does not.
ary = [1,-100,127,128,32767,987.654321098 / 100.0,12345,123456,-32767,-123456,"abcdef"]
$x = ary.pack($format)
ary2 = $x.unpack($format)

test_ok(ary.length == ary2.length)
test_ok(ary.join(':') == ary2.join(':'))
test_ok($x =~ /def/)

test_check "math"
test_ok(Math.sqrt(4) == 2)

include Math
test_ok(sqrt(4) == 2)

test_check "struct"
struct_test = Struct.new("Test", :foo, :bar)
test_ok(struct_test == Struct::Test)

test = struct_test.new(1, 2)
test_ok(test.foo == 1 && test.bar == 2)
test_ok(test[0] == 1 && test[1] == 2)

a, b = test.to_a
test_ok(a == 1 && b == 2)

test[0] = 22
test_ok(test.foo == 22)

test.bar = 47
test_ok(test.bar == 47)

test_check "variable"
test_ok($$.instance_of?(Fixnum))

# read-only variable
begin
  $$ = 5
  test_ok false
rescue NameError
  test_ok true
end

foobar = "foobar"
$_ = foobar
test_ok($_ == foobar)

test_check "trace"
$x = 1234
$y = 0
trace_var :$x, proc{$y = $x}
$x = 40414
test_ok($y == $x)

untrace_var :$x
$x = 19660208
test_ok($y != $x)

trace_var :$x, proc{$x *= 2}
$x = 5
test_ok($x == 10)

untrace_var :$x

test_check "defined?"

test_ok(defined?($x))		# global variable
test_ok(defined?($x) == 'global-variable')# returns description

foo=5
test_ok(defined?(foo))		# local variable

test_ok(defined?(Array))		# constant
test_ok(defined?(Object.new))	# method
test_ok(!defined?(Object.print))	# private method
test_ok(defined?(1 == 2))		# operator expression

def defined_test
  return !defined?(yield)
end

test_ok(defined_test)		# not iterator
test_ok(!defined_test{})		# called as iterator

test_check "alias"
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
test_ok(x.bar == "foo")
test_ok(x.baz == "foo+foo")

# test_check for cache
test_ok(x.baz == "foo+foo")

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
test_ok(!x.foo)
test_ok(x.bar)
test_ok(!x.quux)

test_check "gc"
begin
  1.upto(10000) {
    tmp = [0,1,2,3,4,5,6,7,8,9]
  }
  tmp = nil
  test_ok true
rescue
  test_ok false
end

if $failed > 0
  printf "test: %d failed %d\n", $ntest, $failed
else
  printf "end of test(test: %d)\n", $ntest
end
