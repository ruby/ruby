foo {
}
foo { |a|
}
foo { |a,|
}
foo { |a,; x|
}
foo { |a, b|
}
foo(1) {
  nil
}
foo { |a, *b|
  nil
}
foo { |a, *|
  nil
}
foo {
  bar
}
foo.bar { |(a, b), c|
  d
}
foo.bar { |*a; b|
}
foo.bar { |a; b|
}
foo.bar { |; a, b|
}
foo.bar { |*|
  d
}
foo.bar { |(*)|
  d
}
foo.bar { |((*))|
  d
}
foo.bar { |(a, (*))|
  d
}
foo.bar { |(a, b)|
  d
}
foo.bar {
}.baz
m do
rescue Exception => e
end
m do
  foo
rescue Exception => bar
  bar
end
m do
  bar
rescue SomeError, *bar
  baz
end
m do
  bar
rescue SomeError, *bar => exception
  baz
end
m do
  bar
rescue *bar
  baz
end
m do
  bar
rescue LoadError
end
m do
  bar
rescue
else
  baz
end
m do
  bar
rescue *bar => exception
  baz
end
m do
ensure
end
m do
rescue
ensure
end
bar {
  _1 + _2
}
