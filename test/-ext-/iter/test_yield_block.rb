# frozen_string_literal: false
require 'test/unit'
require '-test-/iter'

module TestIter
end

class TestIter::YieldBlock < Test::Unit::TestCase
  class YieldTest
    include Bug::Iter::Yield
    attr_reader :blockarg
    def test(arg, &block)
      block.call(arg) {|blockarg| @blockarg = blockarg}
    end
    def call_proc(&block)
      block.call {}
    end
    def call_lambda(&block)
      block.call &->{}
    end
  end

  def test_yield_block
    a = YieldTest.new
    a.yield_block(:test, "foo") {|x, &b| assert_kind_of(Proc, b); b.call(x)}
    assert_equal("foo", a.blockarg)
  end

  def test_yield_lambda
    a = YieldTest.new
    assert_not_predicate a.yield_block(:call_proc) {|&b| b}, :lambda?
    assert_predicate a.yield_block(:call_lambda) {|&b| b}, :lambda?
  end
end
