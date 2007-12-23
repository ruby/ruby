#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %{
  def foo(&block)
    yield if block
  end
  foo(&:bar)
}, '[ruby-core:14279]'
