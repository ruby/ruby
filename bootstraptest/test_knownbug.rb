#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  begin
    raise
  rescue
    counter = 2
    while true
      counter -= 1
      break if counter == 0
      next
      retry
    end
  end
}, 'reported by Yusuke ENDOH'

assert_normal_exit %q{
  counter = 2
  while true
    counter -= 1
    break if counter == 0
    next
    "#{ break }"
  end
}, 'reported by Yusuke ENDOH'
