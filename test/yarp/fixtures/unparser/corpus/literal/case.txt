case
when bar
  baz
when baz
  bar
end
case foo
when bar
when baz
  bar
end
case foo
when bar
  baz
when baz
  bar
end
case foo
when bar, baz
  :other
end
case foo
when *bar
  :value
end
case foo
when bar
  baz
else
  :foo
end
case foo
when *bar | baz
end
case foo
when *bar.baz=1
end
