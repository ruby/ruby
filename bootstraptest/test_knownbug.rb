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
