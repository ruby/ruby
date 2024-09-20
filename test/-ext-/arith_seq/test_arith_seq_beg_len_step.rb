# frozen_string_literal: false
require 'test/unit'

class Test_ArithSeq < Test::Unit::TestCase
  def test_beg_len_step
    assert_separately([], <<-"end;") #do
      require '-test-/arith_seq/beg_len_step'

      r, = Enumerator::ArithmeticSequence.__beg_len_step__([1, 2, 3], 0, 0)
      assert_equal(false, r)

      r, = Enumerator::ArithmeticSequence.__beg_len_step__([1, 2, 3], 1, 0)
      assert_equal(false, r)

      r, = Enumerator::ArithmeticSequence.__beg_len_step__([1, 2, 3], 3, 0)
      assert_equal(false, r)

      r, = Enumerator::ArithmeticSequence.__beg_len_step__(1..3, 0, 0)
      assert_equal(nil, r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__(1..3, 1, 0)
      assert_equal([true, 1, 0, 1], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__(1..3, 2, 0)
      assert_equal([true, 1, 1, 1], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__(1..3, 3, 0)
      assert_equal([true, 1, 2, 1], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__(1..3, 4, 0)
      assert_equal([true, 1, 3, 1], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__(1..3, 5, 0)
      assert_equal([true, 1, 3, 1], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__((-10..10).step(2), 24, 0)
      assert_equal([true, 14, 0, 2], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__((-10..10).step(3), 24, 0)
      assert_equal([true, 14, 0, 3], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__((-10..10).step(3), 22, 0)
      assert_equal([true, 12, 0, 3], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__((-10..10).step(-3), 22, 0)
      assert_equal([true, 10, 3, -3], r)

      r = Enumerator::ArithmeticSequence.__beg_len_step__(1..3, 0, 1)
      assert_equal([true, 1, 3, 1], r)
    end;
  end
end
