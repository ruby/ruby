#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  t = Thread.new { system("false") }
  t.join
  $? ? :ng : :ok
}
