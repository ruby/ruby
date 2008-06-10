#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  class C
    define_method(:foo) {
      if block_given?
        :ng
      else
        :ok
      end
    }
  end
  C.new.foo {}
}, '[ruby-core:14813]'

assert_equal 'ok', %q{
  class C
    define_method(:foo) {
      if block_given?
        :ng
      else
        :ok
      end
    }
  end
  C.new.foo
}, '[ruby-core:14813]'

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

