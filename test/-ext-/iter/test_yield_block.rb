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
  end

  def test_yield_block
    a = YieldTest.new
    a.yield_block(:test, "foo") {|x, &b| assert_kind_of(Proc, b); b.call(x)}
    assert_equal("foo", a.blockarg)
  end
end
