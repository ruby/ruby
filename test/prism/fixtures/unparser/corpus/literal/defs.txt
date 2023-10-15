def self.foo
end

def self.foo
  bar
end

def self.foo
  bar
  baz
end

def Foo.bar
  bar
end

def (foo { |bar|
}).bar
  bar
end

def (foo(1)).bar
  bar
end

def (Foo::Bar.baz).bar
  baz
end

def (Foo::Bar).bar
  baz
end

def Foo.bar
  baz
end

def foo.bar
  baz
end
