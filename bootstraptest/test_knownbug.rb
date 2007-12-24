#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  # this cause "called on terminated object".
  ObjectSpace.each_object(Module) {|m| m.name.inspect }
  :ok
}
