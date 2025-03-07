# Tests of Ruby methods that ZJIT can currently compile.
# make btest BTESTS=bootstraptest/test_zjit.rb RUN_OPTS="--zjit"

assert_equal 'nil', %q{
  def test = nil
  test; test.inspect
}

assert_equal '1', %q{
  def test = 1
  test; test
}

assert_equal '3', %q{
  def test = 1 + 2
  test; test
}

assert_equal '[6, 3]', %q{
  def test(a, b) = a + b
  [test(2, 4), test(1, 2)]
}

# Test argument ordering
assert_equal '2', %q{
  def test(a, b) = a - b
  test(6, 4)
}

assert_equal '6', %q{
  def test(a, b, c) = a + b + c
  test(1, 2, 3)
}
