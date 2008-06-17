#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'A', %q{
  class A
    @@a = 'A'
    def a=(x)
      @@a = x
    end
    def a
      @@a
    end
  end

  B = A.dup
  B.new.a = 'B'
  A.new.a
}
