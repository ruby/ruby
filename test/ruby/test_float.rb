require 'test/unit'

$KCODE = 'none'

class TestFloat < Test::Unit::TestCase
  def test_float
    assert_equal(2, 2.6.floor)
    assert_equal(-3, (-2.6).floor)
    assert_equal(3, 2.6.ceil)
    assert_equal(-2, (-2.6).ceil)
    assert_equal(2, 2.6.truncate)
    assert_equal(-2, (-2.6).truncate)
    assert_equal(3, 2.6.round)
    assert_equal(-2, (-2.4).truncate)
    assert((13.4 % 1 - 0.4).abs < 0.0001)
  end

  def test_nan
    nan = 0.0/0
    def nan.test(v)
      extend Test::Unit::Assertions
      assert(self != v)
      assert_equal(false, (self < v))
      assert_equal(false, (self > v))
      assert_equal(false, (self <= v))
      assert_equal(false, (self >= v))
    end
    nan.test(nan)
    nan.test(0)
    nan.test(1)
    nan.test(-1)
    nan.test(1000)
    nan.test(-1000)
    nan.test(1_000_000_000_000)
    nan.test(-1_000_000_000_000)
    nan.test(100.0);
    nan.test(-100.0);
    nan.test(0.001);
    nan.test(-0.001);
    nan.test(1.0/0);
    nan.test(-1.0/0);
  end

  def test_precision
    #s = "3.7517675036461267e+17"
    #assert(s == sprintf("%.16e", s.to_f))
    f = 3.7517675036461267e+17
    assert_equal(f, sprintf("%.16e", f).to_f)
  end
end
