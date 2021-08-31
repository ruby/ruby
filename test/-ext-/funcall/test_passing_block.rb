# frozen_string_literal: false
require 'test/unit'

class TestFuncall < Test::Unit::TestCase
  module Relay
    def self.target(*args, **kw, &block)
      yield(*args, **kw) if block
    end
  end
  require '-test-/funcall'

  def test_with_funcall2
    ok = nil
    Relay.with_funcall2("feature#4504") {|arg| ok = arg || true}
    assert_nil(ok)
  end

  def test_with_funcall_passing_block
    ok = nil
    Relay.with_funcall_passing_block("feature#4504") {|arg| ok = arg || true}
    assert_equal("feature#4504", ok)
  end

  def test_with_funcall_passing_block_kw
    block = ->(*a, **kw) { [a, kw] }
    assert_equal([[1], {}], Relay.with_funcall_passing_block_kw(0, 1, &block))
    assert_equal([[{a: 1}], {}], Relay.with_funcall_passing_block_kw(0, a: 1, &block))
    assert_equal([[], {a: 1}], Relay.with_funcall_passing_block_kw(1, a: 1, &block))
    assert_equal([[1], {a: 1}], Relay.with_funcall_passing_block_kw(1, 1, a: 1, &block))
    assert_equal([[], {a: 1}], Relay.with_funcall_passing_block_kw(3, a: 1, &block))
  end

  def test_with_funcallv_public_kw
    o = Object.new
    def o.foo(*args, **kw)
      [args, kw]
    end
    def o.bar(*args, **kw)
      [args, kw]
    end
    o.singleton_class.send(:private, :bar)
    def o.baz(arg)
      arg
    end
    assert_equal([[1], {}], Relay.with_funcallv_public_kw(o, :foo, 0, 1))
    assert_equal([[{a: 1}], {}], Relay.with_funcallv_public_kw(o, :foo, 0, a: 1))
    assert_equal([[], {a: 1}], Relay.with_funcallv_public_kw(o, :foo, 1, a: 1))
    assert_equal([[1], {a: 1}], Relay.with_funcallv_public_kw(o, :foo, 1, 1, a: 1))
    assert_equal([[], {a: 1}], Relay.with_funcallv_public_kw(o, :foo, 3, a: 1))
  end

  def test_with_yield_splat_kw
    block = ->(*a, **kw) { [a, kw] }
    assert_equal([[1], {}], Relay.with_yield_splat_kw(0, [1], &block))
    assert_equal([[{a: 1}], {}], Relay.with_yield_splat_kw(0, [{a: 1}], &block))
    assert_equal([[], {a: 1}], Relay.with_yield_splat_kw(1, [{a: 1}], &block))
    assert_equal([[1], {a: 1}], Relay.with_yield_splat_kw(1, [1, {a: 1}], &block))
    assert_equal([[], {a: 1}], Relay.with_yield_splat_kw(3, [{a: 1}], &block))
  end
end
