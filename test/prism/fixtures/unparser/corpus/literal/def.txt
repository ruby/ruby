def foo
  a
rescue
  b
else
  c
ensure
  d
end

def foo
  a rescue b
rescue
  b
else
  c
ensure
  d
end

def foo(bar:, baz:)
end

def foo
end

def foo
  bar
end

def foo
  foo
rescue
  bar
ensure
  baz
end

def foo
  bar
ensure
  baz
end

def foo
  bar
rescue
  baz
end

def foo(bar)
  bar
end

def foo(bar, baz)
  bar
end

def foo(bar = ())
  bar
end

def foo(bar = (baz; nil))
end

def foo(bar = true)
  bar
end

def foo(bar, baz = true)
  bar
end

def foo(bar: 1)
end

def foo(bar: baz)
end

def foo(bar: bar())
end

def foo(*)
  bar
end

def foo(*bar)
  bar
end

def foo(bar, *baz)
  bar
end

def foo(baz = true, *bor)
  bar
end

def foo(baz = true, *bor, &block)
  bar
end

def foo(bar, baz = true, *bor)
  bar
end

def foo(&block)
  bar
end

def foo(bar, &block)
  bar
end

def foo
  bar
  baz
end

def f(((a)))
end

def foo(bar:, baz: "value")
end

def f
  <<-HEREDOC
    #{}
  HEREDOC
end

def f
  %()
end
