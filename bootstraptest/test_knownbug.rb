#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_finish 1, %q{
  r, w = IO.pipe
  t1 = Thread.new { r.sysread(10) }
  t2 = Thread.new { r.sysread(10) }
  sleep 0.1
  w.write "a"
  sleep 0.1
  w.write "a"
}, '[ruby-dev:31866]'
