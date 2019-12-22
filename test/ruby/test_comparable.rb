# frozen_string_literal: false
require 'test/unit'

class TestComparable < Test::Unit::TestCase
  def setup
    @o = Object.new
    @o.extend(Comparable)
  end
  def cmp(b)
    class << @o; self; end.class_eval {
      undef :<=>
      define_method(:<=>, b)
    }
  end

  def test_equal
    cmp->(x) do 0; end
    assert_equal(true, @o == nil)
    cmp->(x) do 1; end
    assert_equal(false, @o == nil)
    cmp->(x) do nil; end
    assert_equal(false, @o == nil)

    cmp->(x) do raise NotImplementedError, "Not a RuntimeError" end
    assert_raise(NotImplementedError) { @o == nil }

    bug7688 = 'Comparable#== should not silently rescue' \
              'any Exception [ruby-core:51389] [Bug #7688]'
    cmp->(x) do raise StandardError end
    assert_raise(StandardError, bug7688) { @o == nil }
    cmp->(x) do "bad value"; end
    assert_raise(ArgumentError, bug7688) { @o == nil }
  end

  def test_gt
    cmp->(x) do 1; end
    assert_equal(true, @o > nil)
    cmp->(x) do 0; end
    assert_equal(false, @o > nil)
    cmp->(x) do -1; end
    assert_equal(false, @o > nil)
  end

  def test_ge
    cmp->(x) do 1; end
    assert_equal(true, @o >= nil)
    cmp->(x) do 0; end
    assert_equal(true, @o >= nil)
    cmp->(x) do -1; end
    assert_equal(false, @o >= nil)
  end

  def test_lt
    cmp->(x) do 1; end
    assert_equal(false, @o < nil)
    cmp->(x) do 0; end
    assert_equal(false, @o < nil)
    cmp->(x) do -1; end
    assert_equal(true, @o < nil)
  end

  def test_le
    cmp->(x) do 1; end
    assert_equal(false, @o <= nil)
    cmp->(x) do 0; end
    assert_equal(true, @o <= nil)
    cmp->(x) do -1; end
    assert_equal(true, @o <= nil)
  end

  def test_between
    cmp->(x) do 0 <=> x end
    assert_equal(false, @o.between?(1, 2))
    assert_equal(false, @o.between?(-2, -1))
    assert_equal(true, @o.between?(-1, 1))
    assert_equal(true, @o.between?(0, 0))
  end

  def test_clamp
    cmp->(x) do 0 <=> x end
    assert_equal(1, @o.clamp(1, 2))
    assert_equal(-1, @o.clamp(-2, -1))
    assert_equal(@o, @o.clamp(-1, 3))

    assert_equal(1, @o.clamp(1, 1))
    assert_equal(@o, @o.clamp(0, 0))

    assert_raise_with_message(ArgumentError, 'min argument must be smaller than max argument') {
      @o.clamp(2, 1)
    }
  end

  def test_clamp_with_range
    cmp->(x) do 0 <=> x end
    assert_equal(1, @o.clamp(1..2))
    assert_equal(-1, @o.clamp(-2..-1))
    assert_equal(@o, @o.clamp(-1..3))

    assert_equal(1, @o.clamp(1..1))
    assert_equal(@o, @o.clamp(0..0))

    assert_equal(1, @o.clamp(1..))
    assert_equal(1, @o.clamp(1...))
    assert_equal(@o, @o.clamp(0..))
    assert_equal(@o, @o.clamp(0...))
    assert_equal(@o, @o.clamp(..2))
    assert_equal(-1, @o.clamp(-2..-1))
    assert_equal(@o, @o.clamp(-2..0))
    assert_equal(@o, @o.clamp(-2..))
    assert_equal(@o, @o.clamp(-2...))

    exc = [ArgumentError, 'cannot clamp with an exclusive range']
    assert_raise_with_message(*exc) {@o.clamp(1...2)}
    assert_raise_with_message(*exc) {@o.clamp(0...2)}
    assert_raise_with_message(*exc) {@o.clamp(-1...0)}
    assert_raise_with_message(*exc) {@o.clamp(...2)}

    assert_raise_with_message(ArgumentError, 'min argument must be smaller than max argument') {
      @o.clamp(2..1)
    }
  end

  def test_err
    assert_raise(ArgumentError) { 1.0 < nil }
    assert_raise(ArgumentError) { 1.0 < Object.new }
    e = EnvUtil.labeled_class("E\u{30a8 30e9 30fc}")
    assert_raise_with_message(ArgumentError, /E\u{30a8 30e9 30fc}/) {
      1.0 < e.new
    }
  end

  def test_inversed_compare
    bug7870 = '[ruby-core:52305] [Bug #7870]'
    assert_nothing_raised(SystemStackError, bug7870) {
      assert_nil(Time.new <=> "")
    }
  end

  def test_no_cmp
    bug9003 = '[ruby-core:57736] [Bug #9003]'
    assert_nothing_raised(SystemStackError, bug9003) {
      @o <=> @o.dup
    }
  end
end
