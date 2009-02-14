#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit(<<'End', '[ruby-dev:37934]')
  Process.setrlimit(:NPROC, 1)
  system("ls")
End
