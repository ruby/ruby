# frozen_string_literal: false
require 'test/unit'

class Test_ArithSeq < Test::Unit::TestCase
  def test_extract_with_arith_seq
    assert_separately([], <<-"end;") #do
      require '-test-/arith_seq/extract'

      b, e, s, f, r = Enumerator::ArithmeticSequence.__extract__(1.step(10, 2))
      assert_equal([1, 10, 2, 0, 1], [b, e, s, f, r])

      b, e, s, f, r = Enumerator::ArithmeticSequence.__extract__((1..10) % 2)
      assert_equal([1, 10, 2, 0, 1], [b, e, s, f, r])

      b, e, s, f, r = Enumerator::ArithmeticSequence.__extract__((1...10) % 2)
      assert_equal([1, 10, 2, 1, 1], [b, e, s, f, r])
    end;
  end

  def test_extract_with_range
    assert_separately([], <<-"end;") #do
      require '-test-/arith_seq/extract'

      b, e, s, f, r = Enumerator::ArithmeticSequence.__extract__(1..10)
      assert_equal([1, 10, 1, 0, 1], [b, e, s, f, r])

      b, e, s, f, r = Enumerator::ArithmeticSequence.__extract__(1...10)
      assert_equal([1, 10, 1, 1, 1],  [b, e, s, f, r])
    end;
  end

  def test_extract_with_others
    assert_separately([], <<-"end;") #do
      require '-test-/arith_seq/extract'

      b, e, s, f, r = Enumerator::ArithmeticSequence.__extract__(nil)
      assert_equal([nil, nil, nil, nil, 0], [b, e, s,  f, r])
    end;
  end
end
