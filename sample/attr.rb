class Foo
  attr("test", %TRUE)
end

foo = Foo.new
foo.test = 10
print(foo.test, "\n")
foo._inspect.print
print("\n")
