class foo
  def foo
    eval("
def baz
  print(\"bar\n\")
end")
  end
end

class bar:foo
  def bar
    baz()
  end
end

f = foo.new
b = bar.new

b.foo
b.bar
f.baz
