if /foo/
  bar
end
if 3
  9
end
if 4
  5
else
  6
end
unless 3
  nil
end
unless 3
  9
end
if foo
end

module A
  foo = bar if foo
end

module B
  foo = bar unless foo
end
unless foo
  foo = bar
end
if foo { |pair|
  pair
}
  pair = :foo
  foo
end
