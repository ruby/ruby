at_exit {
  foo
}

def foo
  puts caller(0)
end
