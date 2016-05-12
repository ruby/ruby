# frozen_string_literal: false
require_relative 'base'

class TestMkmf
  class TestLibs < TestMkmf
    def test_split_libs
      assert_equal(%w[-lfoo -lbar], split_libs("-lfoo -lbar"))
      assert_equal(%w[-ObjC -framework\ Ruby], split_libs("-ObjC -framework Ruby"), 'Bug #6987')
    end

    def assert_in_order(array, x, y, mesg = nil)
      mesg = "#{x} must proceed to #{y}#{': ' if mesg}#{mesg}"
      assert_operator(array.index(x), :<, array.rindex(y), mesg)
    end

    def test_merge_simple
      bug = '[ruby-dev:21765]'
      assert_equal([], merge_libs(%w[]))
      assert_equal(%w[a b], merge_libs(%w[a], %w[b]))
      array = merge_libs(%w[a c], %w[b])
      assert_in_order(array, "a", "c", bug)
    end

    def test_merge_seq
      bug = '[ruby-dev:21765]'
      array = merge_libs(%w[a c d], %w[c b e])
      assert_in_order(array, "a", "c", bug)
      assert_in_order(array, "c", "d", bug)
      assert_in_order(array, "c", "b", bug)
      assert_in_order(array, "b", "e", bug)
    end

    def test_merge_seq_pre
      bug = '[ruby-dev:21765]'
      array = merge_libs(%w[a c d], %w[b c d e])
      assert_in_order(array, "a", "c", bug)
      assert_in_order(array, "c", "d", bug)
      assert_in_order(array, "b", "c", bug)
      assert_in_order(array, "d", "e", bug)
    end

    def test_merge_cyclic
      bug = '[ruby-dev:21765]'
      array = merge_libs(%w[a c d], %w[b c b])
      assert_in_order(array, "a", "c", bug)
      assert_in_order(array, "c", "d", bug)
      assert_in_order(array, "b", "c", bug)
      assert_in_order(array, "c", "b", bug)
    end

    def test_merge_cyclic_2
      bug = '[ruby-dev:21765]'
      array = merge_libs(%w[a c a d], %w[b c b])
      assert_in_order(array, "a", "c", bug)
      assert_in_order(array, "c", "a", bug)
      assert_in_order(array, "c", "d", bug)
      assert_in_order(array, "a", "d", bug)
      assert_in_order(array, "b", "c", bug)
      assert_in_order(array, "c", "b", bug)
    end

    def test_merge_reversal
      bug = '[ruby-dev:22440]'
      array = merge_libs(%w[a b c], %w[c d a])
      assert_in_order(array, "a", "b" , bug)
      assert_in_order(array, "c", "d" , bug)
      ## assume that a and c have no dependency
    end

    def test_merge_reversal_followed
      bug7467 = '[ruby-core:50314] [Bug #7467]'
      array = nil
      assert_nothing_raised(bug7467) {
        array = merge_libs(%w[a b c d e f g h], %w[d c d e], [])
      }
      assert_in_order(array, "a", "b", bug7467)
      assert_in_order(array, "b", "c", bug7467)
      assert_in_order(array, "c", "d", bug7467)
      assert_in_order(array, "d", "e", bug7467)
      assert_in_order(array, "e", "f", bug7467)
      assert_in_order(array, "f", "g", bug7467)
      assert_in_order(array, "g", "h", bug7467)
      assert_in_order(array, "d", "c", bug7467)
      assert_in_order(array, "c", "e", bug7467)
    end
  end
end if RUBY_ENGINE == "ruby"
