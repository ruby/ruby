assert_equal 'true', %q{
  def nil_nil = nil == nil
  nil_nil
}

assert_equal 'true', %q{
  def lt(a, b) = a < b
  lt(1, 2)
  lt('a', 'b')
}

assert_equal '3', %q{
  def foo = 2
  def bar = 1 + foo + nil.to_i
  bar
}
