#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit(<<'End', '[ruby-dev:37934]')
  Thread.new { sleep 1; Thread.kill Thread.main }
  Process.setrlimit(:NPROC, 1)
  fork {}
End

