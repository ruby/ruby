require 'test/unit'

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

  def nan_test(x,y)
    extend Test::Unit::Assertions
    assert(x != y)
    assert_equal(false, (x < y))
    assert_equal(false, (x > y))
    assert_equal(false, (x <= y))
    assert_equal(false, (x >= y))
  end
  def test_nan
    nan = 0.0/0
    nan_test(nan, nan)
    nan_test(nan, 0)
    nan_test(nan, 1)
    nan_test(nan, -1)
    nan_test(nan, 1000)
    nan_test(nan, -1000)
    nan_test(nan, 1_000_000_000_000)
    nan_test(nan, -1_000_000_000_000)
    nan_test(nan, 100.0);
    nan_test(nan, -100.0);
    nan_test(nan, 0.001);
    nan_test(nan, -0.001);
    nan_test(nan, 1.0/0);
    nan_test(nan, -1.0/0);
  end

  def test_precision
    #s = "3.7517675036461267e+17"
    #assert(s == sprintf("%.16e", s.to_f))
    f = 3.7517675036461267e+17
    assert_equal(f, sprintf("%.16e", f).to_f)
  end

  def test_symmetry_bignum # [ruby-bugs-ja:118]
    a = 100000000000000000000000
    b = 100000000000000000000000.0
    assert_equal(a == b, b == a)
  end

  def test_strtod
    a = Float("0")
    assert(a.abs < Float::EPSILON)
    a = Float("0.0")
    assert(a.abs < Float::EPSILON)
    a = Float("+0.0")
    assert(a.abs < Float::EPSILON)
    a = Float("-0.0")
    assert(a.abs < Float::EPSILON)
    a = Float("0.0000000000000000001")
    assert(a != 0.0)
    a = Float("+0.0000000000000000001")
    assert(a != 0.0)
    a = Float("-0.0000000000000000001")
    assert(a != 0.0)
    a = Float(".0")
    assert(a.abs < Float::EPSILON)
    a = Float("+.0")
    assert(a.abs < Float::EPSILON)
    a = Float("-.0")
    assert(a.abs < Float::EPSILON)
    a = Float("0.")
    assert(a.abs < Float::EPSILON)
    a = Float("+0.")
    assert(a.abs < Float::EPSILON)
    a = Float("-0.")
    assert(a.abs < Float::EPSILON)
    assert_raise(ArgumentError){Float(".")}
    assert_raise(ArgumentError){Float("+")}
    assert_raise(ArgumentError){Float("+.")}
    assert_raise(ArgumentError){Float("-")}
    assert_raise(ArgumentError){Float("-.")}
    # add expected behaviour here.
  end
end
