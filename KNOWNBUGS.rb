#
# IMPORTANT: Always keep the first 7 lines (comments),
# even if this file is otherwise empty.
#
# This test file includes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit("#{<<-";END;"}", timeout: 5)
begin
  require "-test-/typeddata"
rescue LoadError
else
  n = 1 << 20
  Bug::TypedData.make(n)
end
;END;
