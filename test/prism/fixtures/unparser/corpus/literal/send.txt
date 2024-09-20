module A
  foo ||= ((a, _) = b)
end

module A
  local = 1
  local.bar
end
class A
end.bar
module A
end.bar
begin
rescue
end.bar
case (def foo
end; :bar)
when bar
end.baz
case foo
when bar
end.baz
class << self
end.bar
def self.foo
end.bar
def foo
end.bar
until foo
end.bar
while foo
end.bar
loop {
}.bar
if foo
end.baz
(/bar/ =~ :foo).foo
(1..2).max
(foo =~ /bar/).foo
/bar/ =~ :foo
/bar/ =~ foo
1..2.max
A.foo
FOO()
a&.b
a.foo
foo
foo << (bar * baz)
foo =~ /bar/
foo(&(foo || bar))
foo(&block)
foo(*args, &block)
foo(*arguments)
foo(1, 2)
foo(bar)
foo(bar, *args)
foo(foo =~ /bar/)
foo.bar(&baz)
foo.bar(*arga, foo, *argb)
foo.bar(*args)
foo.bar(*args, foo)
foo.bar(:baz, &baz)
foo.bar(baz: boz)
foo.bar(foo, "baz" => boz)
foo.bar(foo, *args)
foo.bar(foo, *args, &block)
foo.bar(foo, {})
foo.bar({ foo: boz }, boz)
foo.bar=:baz
foo(a: b)
foo.&(a: b)
foo.&(**a)
foo[*baz]
foo[1, 2]
foo[]
self.foo
self.foo=:bar
(a + b) / (c - d)
(a + b) / c.-(e, f)
(a + b) / c.-(*f)
x(**foo)
foo&.!
foo.~(b)
a&.+(b)
