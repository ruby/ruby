#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  r = Range.allocate
  def r.<=>(o) true end
  r.instance_eval { initialize r, r }
  r.inspect
}


