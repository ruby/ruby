#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  counter = 2
  while true
    counter -= 1
    next if counter != 0
    break
  end
}, '[ruby-core:14385]'
