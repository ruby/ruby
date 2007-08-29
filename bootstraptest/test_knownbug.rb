#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

# massign
assert_equal 'ok', %q{
  def m()
    yield :ng
  end
  r = :ok
  m {|(r)|}
  r
}, '[ruby-dev:31507]'

assert_equal 'ok', %q{
  begin
    catch {|t| throw t, :ok }
  rescue ArgumentError
    :ng
  end
}, '[ruby-dev:31609]'
