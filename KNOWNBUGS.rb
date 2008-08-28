#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  class Foo
    define_method(:foo) do |&b|
      b.call
    end
  end
  Foo.new.foo do
    break :ok
  end
}, '[ruby-dev:36028]'
