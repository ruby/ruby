require 'test/unit'

$KCODE = 'none'

class TestFloat < Test::Unit::TestCase
  def test_float
    assert_equal(2.6.floor, 2)
    assert_equal((-2.6).floor, -3)
    assert_equal(2.6.ceil, 3)
    assert_equal((-2.6).ceil, -2)
    assert_equal(2.6.truncate, 2)
    assert_equal((-2.6).truncate, -2)
    assert_equal(2.6.round, 3)
    assert_equal((-2.4).truncate, -2)
    assert((13.4 % 1 - 0.4).abs < 0.0001)
    nan = 0.0/0
    def nan.test(v)
      extend Test::Unit::Assertions
      assert(self != v)
      assert_equal((self < v), false)
      assert_equal((self > v), false)
      assert_equal((self <= v), false)
      assert_equal((self >= v), false)
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
    
    #s = "3.7517675036461267e+17"
    #assert(s == sprintf("%.16e", s.to_f))
    f = 3.7517675036461267e+17
    assert_equal(f, sprintf("%.16e", f).to_f)
  end
end
