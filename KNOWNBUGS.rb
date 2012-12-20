#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal('ok', "set_trace_func(proc{|t,|raise if t == 'line'})\n""1\n'ok'")
assert_finish(3, "def m; end\n""set_trace_func(proc{|t,|raise if t == 'return'})\n""m")
