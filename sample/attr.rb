# attribute access example
# output:
#	10
#	#<Foo: @test=10>

class Foo
  attr "test", TRUE
end

foo = Foo.new
foo.test = 10
print foo.test, "\n"
foo._inspect.print
print "\n"
