#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal('ok', "TracePoint.new(:line) {raise}.enable {\n  1\n}\n'ok'")
assert_finish(3, 'def m; end; TracePoint.new(:return) {raise}.enable {m}')
