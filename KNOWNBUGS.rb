#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_normal_exit %q{
  loop do
    def x
      "hello" * 1000
    end
    method(:x).call
  end
}, '[ruby-core:53640] [Bug #8100]'
