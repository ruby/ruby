#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

# catch/throw
assert_equal 'ok', %q{
  begin
    catch {|t| throw t, :ok }
  rescue ArgumentError
    :ng
  end
}, '[ruby-dev:31609]'
