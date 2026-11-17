# frozen_string_literal: false
require 'test/unit'
require '-test-/array/ptr'
require 'objspace'

class Test_Array < Test::Unit::TestCase
  class TestPtr < Test::Unit::TestCase
    def wb_protected?(obj)
      ObjectSpace.dump(obj).include?('"wb_protected":true')
    end

    def test_unfrozen
      ary = [Object.new, 2]
      assert_same(ary[0], Bug::Array.__ptr_first__(ary))
      assert_not_predicate(ary, :frozen?)
      assert_equal(false, wb_protected?(ary))
    end

    def test_frozen
      ary = [Object.new, 2].freeze
      assert_same(ary[0], Bug::Array.__ptr_first__(ary))
      assert_equal(true, wb_protected?(ary))
    end

    def test_shareable
      ary = Ractor.make_shareable([Object.new, 2])
      assert_same(ary[0], Bug::Array.__ptr_first__(ary))
      assert_equal(true, wb_protected?(ary))
    end
  end
end
