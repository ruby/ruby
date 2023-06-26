module A
  foo { |bar|
    while foo
      foo = bar
    end
  }
end

def foo
  foo = bar while foo != baz
end

module A
  foo = bar while foo
end

module A
  foo = bar until foo
end

module A
  while foo
    foo = bar
  end
end

module A
  each { |baz|
    while foo
      foo = bar
    end
  }
end

module A
  each { |foo|
    while foo
      foo = bar
    end
  }
end
x = (begin
  foo
end while baz)
begin
  foo
end while baz
begin
  foo
  bar
end until baz
begin
  foo
  bar
end while baz
while false
end
while false
  3
end
while (foo {
})
  :body
end
until false
end
until false
  3
end
until (foo {
})
  :body
end
