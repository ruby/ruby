#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'false', %q{
  x = Object.new.taint
  class << x
    def to_s; "foo".freeze; end
  end
  x.taint
  [x].join("")
  eval '"foo".freeze.tainted?'
}
