# object cloning & single method test
# output:
#	test2
#	test
#	test
#	clone.rb:13: undefined method `test2' for "#<Object: 0xbfca4>"(Object)
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
