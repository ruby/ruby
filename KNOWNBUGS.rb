#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal %q{[:bar, :foo]}, %q{
  def foo
    klass = Class.new do
      define_method(:bar) do
        return :bar
      end
    end
    [klass.new.bar, :foo]
  end
  foo
}, "[ ruby-Bugs-19304 ]"

