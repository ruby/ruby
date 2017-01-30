#
# IMPORTANT: Always keep the first 7 lines (comments),
# even if this file is otherwise empty.
#
# This test file includes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal "ArgumentError", %{
  def s(a) yield a; end
  begin
    s([1, 2], &lambda { |a,b| [a,b] })
  rescue ArgumentError => e
    e.class
  end
}, '[Bug #12705]'
