foo = Object.new
def foo.test
  print("test\n")
end
bar = foo.clone
def bar.test2
  print("test2\n")
end
bar.test2
bar.test
foo.test
foo.test2
