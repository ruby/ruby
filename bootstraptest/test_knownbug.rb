#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_finish 1, %q{
  r, w = IO.pipe
  Thread.new {
  w << "ab"
  sleep 0.1
  w << "ab"
  }
  p r.gets("abab")
}
