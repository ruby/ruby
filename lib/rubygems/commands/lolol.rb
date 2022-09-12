class Foo < Bar
  def initialize(my_foo)
    @ivar_foo = my_foo
  end
end

obj = Foo.new("Hello")
