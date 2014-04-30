require 'test/unit'
require_relative 'envutil'

class TestCall < Test::Unit::TestCase
  def aaa(a, b=100, *rest)
    res = [a, b]
    res += rest if rest
    return res
  end

  def test_call
    assert_raise(ArgumentError) {aaa()}
    assert_raise(ArgumentError) {aaa}

    assert_equal([1, 100], aaa(1))
    assert_equal([1, 2], aaa(1, 2))
    assert_equal([1, 2, 3, 4], aaa(1, 2, 3, 4))
    assert_equal([1, 2, 3, 4], aaa(1, *[2, 3, 4]))
  end

  def test_callinfo
    bug9622 = '[ruby-core:61422] [Bug #9622]'
    o = Class.new do
      def foo(*args)
        bar(:foo, *args)
      end
      def bar(name)
        name
      end
    end.new
    e = assert_raise(ArgumentError) {o.foo(100)}
    assert_nothing_raised(ArgumentError) {o.foo}
    assert_raise_with_message(ArgumentError, e.message, bug9622) {o.foo(100)}
  end
end
