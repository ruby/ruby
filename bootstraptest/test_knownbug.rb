#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal '0', %q{
  GC.stress = true
  pid = fork {}
  Process.wait pid
  $?.to_i
}, '[ruby-dev:32404]'

assert_match /unterminated string meets end of file/, %q{
  STDERR.reopen(STDOUT)
  eval("\"\xfd".force_encoding("utf-8"))
}, '[ruby-dev:32429]'
