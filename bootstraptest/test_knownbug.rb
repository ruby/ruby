#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 1, %q{
  catch do |t|
    begin
      throw t, 1
      2
    ensure
      3
    end
  end
}, "[ruby-dev:31698]"
