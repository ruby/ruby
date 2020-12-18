# frozen_string_literal: true
require 'test/unit'

class TestMethodCache < Test::Unit::TestCase
  def test_undef
    # clear same
    c0 = Class.new do
      def foo; end
      undef foo
    end

    assert_raise(NoMethodError) do
      c0.new.foo
    end

    c0.class_eval do
      def foo; :ok; end
    end

    assert_equal :ok, c0.new.foo
  end

  def test_undef_with_subclasses
    # with subclasses
    c0 = Class.new do
      def foo; end
      undef foo
    end

    _c1 = Class.new(c0)

    assert_raise(NoMethodError) do
      c0.new.foo
    end

    c0.class_eval do
      def foo; :ok; end
    end

    assert_equal :ok, c0.new.foo
  end

  def test_undef_with_subclasses_complicated
    c0 = Class.new{ def foo; end }
    c1 = Class.new(c0){ undef foo }
    c2 = Class.new(c1)
    c3 = Class.new(c2)
    _c4 = Class.new(c3)

    assert_raise(NoMethodError) do
      c3.new.foo
    end

    c2.class_eval do
      def foo; :c2; end
    end

    assert_raise(NoMethodError) do
      c1.new.foo
    end

    assert_equal :c2, c3.new.foo
  end
end

