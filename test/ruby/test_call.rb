# frozen_string_literal: false
require 'test/unit'

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

  def test_safe_call
    s = Struct.new(:x, :y, :z)
    o = s.new("x")
    assert_equal("X", o.x&.upcase)
    assert_nil(o.y&.upcase)
    assert_equal("x", o.x)
    o&.x = 6
    assert_equal(6, o.x)
    o&.x *= 7
    assert_equal(42, o.x)
    o&.y = 5
    assert_equal(5, o.y)
    o&.z ||= 6
    assert_equal(6, o.z)

    o = nil
    assert_nil(o&.x)
    assert_nothing_raised(NoMethodError) {o&.x = raise}
    assert_nothing_raised(NoMethodError) {o&.x *= raise}
    assert_nothing_raised(NoMethodError) {o&.x *= raise; nil}
  end

  def test_safe_call_evaluate_arguments_only_method_call_is_made
    count = 0
    proc = proc { count += 1; 1 }
    s = Struct.new(:x, :y)
    o = s.new(["a", "b", "c"])

    o.y&.at(proc.call)
    assert_equal(0, count)

    o.x&.at(proc.call)
    assert_equal(1, count)
  end

  def test_safe_call_block_command
    assert_nil(("a".sub! "b" do end&.foo 1))
  end

  def test_safe_call_block_call
    assert_nil(("a".sub! "b" do end&.foo))
  end

  def test_safe_call_block_call_brace
    assert_nil(("a".sub! "b" do end&.foo {}))
    assert_nil(("a".sub! "b" do end&.foo do end))
  end

  def test_safe_call_block_call_command
    assert_nil(("a".sub! "b" do end&.foo 1 do end))
  end

  def test_invalid_safe_call
    h = nil
    assert_raise(NoMethodError) {
      h[:foo] = nil
    }
  end

  def test_call_splat_order
    bug12860 = '[ruby-core:77701] [Bug# 12860]'
    ary = [1, 2]
    assert_equal([1, 2, 1], aaa(*ary, ary.shift), bug12860)
    ary = [1, 2]
    assert_equal([0, 1, 2, 1], aaa(0, *ary, ary.shift), bug12860)
  end
end
