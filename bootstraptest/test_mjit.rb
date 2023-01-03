assert_equal 'true', %q{
  def nil_nil = nil == nil
  nil_nil
}

assert_equal 'true', %q{
  def lt(a, b) = a < b
  lt(1, 2)
  lt('a', 'b')
}
