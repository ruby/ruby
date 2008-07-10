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
    u = 3.7517675036461267e+17
    v = sprintf("%.16e", u).to_f
    assert_in_delta(u, v, u.abs * Float::EPSILON)
    assert_in_delta(u, v, v.abs * Float::EPSILON)
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
    assert(a.abs < Float::EPSILON)
    assert_raise(ArgumentError){Float(".")}
    assert_raise(ArgumentError){Float("+")}
    assert_raise(ArgumentError){Float("+.")}
    assert_raise(ArgumentError){Float("-")}
    assert_raise(ArgumentError){Float("-.")}
    assert_raise(ArgumentError){Float("1e")}
    # add expected behaviour here.
  end

  def test_divmod
    assert_equal([2, 3.5], 11.5.divmod(4))
    assert_equal([-3, -0.5], 11.5.divmod(-4))
    assert_equal([-3, 0.5], (-11.5).divmod(4))
    assert_equal([2, -3.5], (-11.5).divmod(-4))
  end

  def test_div
    assert_equal(2, 11.5.div(4))
    assert_equal(-3, 11.5.div(-4))
    assert_equal(-3, (-11.5).div(4))
    assert_equal(2, (-11.5).div(-4))
  end

  def test_modulo
    assert_equal(3.5, 11.5.modulo(4))
    assert_equal(-0.5, 11.5.modulo(-4))
    assert_equal(0.5, (-11.5).modulo(4))
    assert_equal(-3.5, (-11.5).modulo(-4))
  end

  def test_remainder
    assert_equal(3.5, 11.5.remainder(4))
    assert_equal(3.5, 11.5.remainder(-4))
    assert_equal(-3.5, (-11.5).remainder(4))
    assert_equal(-3.5, (-11.5).remainder(-4))
  end

  def test_to_i
    assert_operator(4611686018427387905.0.to_i, :>, 0)
    assert_operator(4611686018427387904.0.to_i, :>, 0)
    assert_operator(4611686018427387903.8.to_i, :>, 0)
    assert_operator(4611686018427387903.5.to_i, :>, 0)
    assert_operator(4611686018427387903.2.to_i, :>, 0)
    assert_operator(4611686018427387903.0.to_i, :>, 0)
    assert_operator(4611686018427387902.0.to_i, :>, 0)

    assert_operator(1073741825.0.to_i, :>, 0)
    assert_operator(1073741824.0.to_i, :>, 0)
    assert_operator(1073741823.8.to_i, :>, 0)
    assert_operator(1073741823.5.to_i, :>, 0)
    assert_operator(1073741823.2.to_i, :>, 0)
    assert_operator(1073741823.0.to_i, :>, 0)
    assert_operator(1073741822.0.to_i, :>, 0)

    assert_operator((-1073741823.0).to_i, :<, 0)
    assert_operator((-1073741824.0).to_i, :<, 0)
    assert_operator((-1073741824.2).to_i, :<, 0)
    assert_operator((-1073741824.5).to_i, :<, 0)
    assert_operator((-1073741824.8).to_i, :<, 0)
    assert_operator((-1073741825.0).to_i, :<, 0)
    assert_operator((-1073741826.0).to_i, :<, 0)

    assert_operator((-4611686018427387903.0).to_i, :<, 0)
    assert_operator((-4611686018427387904.0).to_i, :<, 0)
    assert_operator((-4611686018427387904.2).to_i, :<, 0)
    assert_operator((-4611686018427387904.5).to_i, :<, 0)
    assert_operator((-4611686018427387904.8).to_i, :<, 0)
    assert_operator((-4611686018427387905.0).to_i, :<, 0)
    assert_operator((-4611686018427387906.0).to_i, :<, 0)
  end
end
