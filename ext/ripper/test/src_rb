# comment
=begin
  embedded document
=end

# literal
1
1000000000000000000000
1.0
1.234e5
1..2
1...3
:symbol
:"dynamic #{sym_embexpr} symbol"
[1,2,3]
{1 => 2}
'string'
"string"
"before #{str_embexpr} after"
"str #@ivar str"
"str #$gvar str"
"string" "concat"
`/bin/true`
{1, 2, 3, 4}
/regexp/
/regexp_with_opt/mioe
/regexp #{regexp_embexpr} after/
%q[string]
%Q[str#{str_embexpr}ing]
%r[regexp]
%w( a b c )
%W( a#{w_emb}b c d )
<<HERE
heredoc line 1
heredoc line 2
heredoc line 3
HERE

# special variables
true
false
nil
self

# def
def a
end
def b()
end
def c(a)
end
def d(a,*rest)
end
def e(a,&block)
end
def f(a,*rest,&block)
end
def g(*rest)
end
def h(&block)
end
def i(*rest,&block)
end
def j(CONST)
end
def k(@ivar)
end
def l($gvar)
end
def n(@@cvar)
end

# alias
alias x b
alias $rest $'     # error
alias $nth $1      # error

# undef
undef warn

# class, module
class C
end
module M
end
class cname
end
class << Object.new
  def self.a
  end
end

# field
$a = 1
$' = 0   # error
$1 = 0   # error
@a = 2
@@a = 3
a = 4
a += 1
a -= 1
a *= 1
a /= 1
a &&= 1
a ||= 1
m.a = 5
m.a += 1
m.a &&= 1
m.a ||= 1
a[1] = 2
a[1] += 1
a[1] &&= 1
a[1] ||= 1
C = 1
C::C = 1
::C = 1
def m
  C = 1      # dynamic const assignment
  C::C = 1   # dynamic const assignment
  ::C = 1    # dynamic const assignment
end

# ref
lvar = $a
lvar = @a
lvar = @@a
lvar = Object
lvar = C
lvar = C::C
lvar = ::C
lvar = a[1]

# unary operator
+1
-1
not 1
!1
~str

# binary operator
1 + 1
1 - 1
1 * 1
1 / 1
1 ** 1
1 ^ 1
1 & 1
1 | 1
1 && 1
1 || 1

# mlhs, mrhs
a, b, c = list
a, = list
a, * = list
a, *b = list
a, (b, c), d, *e = list
mlhs = 1, 2
mlhs = 1, 2, 3, *list
mlhs = *list

# method call
m
m()
m(a)
m(a,a)
m(*a)
m(&b)
m(a,*a)
m(a,&b)
m(a,*a,&b)
m(1=>2)
m(1=>2,*a)
m(1=>2,&b)
m(1=>2,*a,&b)
m ()
m (a)
m (a,a)
m (*a)
m (&b)
m (a,*a)
m (a,&b)
m (a,*a,&b)
m (1=>2)
m (1=>2,*a)
m (1=>2,&b)
m (1=>2,*a,&b)
m a
m a,a
m *a
m &b
m a,*a
m a,&b
m a,*a,&b
m 1=>2
m 1=>2,*a
m 1=>2,&b
m 1=>2,*a,&b
obj.m
obj.m()
obj.m(a)
obj.m(a,a)
obj.m(*a)
obj.m(&b)
obj.m(a,*a)
obj.m(a,&b)
obj.m(a,*a,&b)
obj.m(1=>2)
obj.m(1=>2,*a)
obj.m(1=>2,&b)
obj.m(1=>2,*a,&b)
obj.m ()
obj.m (a)
obj.m (a,a)
obj.m (*a)
obj.m (&b)
obj.m (a,*a)
obj.m (a,&b)
obj.m (a,*a,&b)
obj.m (1=>2)
obj.m (1=>2)
obj.m (1=>2,*a)
obj.m (1=>2,&b)
obj.m (1=>2,*a,&b)
obj.m a
obj.m a,a
obj.m *a
obj.m &b
obj.m a,*a
obj.m a,&b
obj.m a,*a,&b
obj.m 1=>2
obj.m 1=>2,*a
obj.m 1=>2,&b
obj.m 1=>2,*a,&b

# ambiguous argument
m +1
m /r/

# iterator
[1,2,3].each do |i|
  print i
end
{1=>true}.each do |k,v|
  puts k
end
[1,2,3].each {|i| print i }
[1].each {|a,| }
[1].each {|*b| }
[1].each {|a,*b| }
[1].each {|&block| }
[1].each {|a,&block| }
[1].each {|a,*b,&block| }
a = lambda() {|n| n * n }
a = lambda () {|n| n * n }
a = lambda (a) {|n| n * n }
a = lambda (a,b) {|n| n * n }

# BEGIN, END
BEGIN { }
END { }

# if, unless
1 if true
2 unless false
if false
  5
elsif false
  6
elsif false then 7
else
  8
end
if m
end
unless 1
  2
end
unless m
end
0 ? 1 : 2

# case
case 'a'
when 'b'
  ;
when 'c' then 1
else
  2
end
case
when 1
when 2
when 3
else
end
case 1
else
end
case
else
end

# while, until, for
while true
  break
  next
  redo
end
begin
  break
end while true
until false
  break
  next
  redo
end
begin
  break
end until false
for x in m()
  break
  next
  redo
end
0 until true
1 while false

# begin, rescue, else, ensure
begin
  1
rescue StandardError => er
  2
rescue => er
  3
  retry
else
  4
ensure
  5
end
a = 1 rescue 2

# jumps
def m
  redo
  yield
  yield nil
  super
  super 1
  return
  return nil
end

# defined
defined? f
defined?(f)

n = 1 \
+ 1

__END__
