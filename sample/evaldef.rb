# method definition by eval()
# output:
#	bar
#	(eval):26: method `baz' not available for "#<foo: 0xbfc5c>"(foo)

class Foo
  def foo
    eval("
def baz
  print(\"bar\n\")
end")
  end
end

class Bar : Foo
  def bar
    baz()
  end
end

f = Foo.new
b = Bar.new

b.foo
b.bar
f.baz
