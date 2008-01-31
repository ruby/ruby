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
    assert_equal(36893488147419111424,
                 36893488147419107329.0.to_i)
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

  def test_to_s
    inf = 1.0 / 0.0
    assert_equal("Infinity", inf.to_s)
    assert_equal("-Infinity", (-inf).to_s)
    assert_equal("NaN", (inf / inf).to_s)

    assert_equal("1.0e+14", 10000_00000_00000.0.to_s)
  end

  def test_coerce
    assert_equal(Float, 1.0.coerce(1).first.class)
  end

  def test_plus
    assert_equal(4.0, 2.0.send(:+, 2))
    assert_equal(4.0, 2.0.send(:+, (2**32).coerce(2).first))
    assert_equal(4.0, 2.0.send(:+, 2.0))
    assert_raise(TypeError) { 2.0.send(:+, nil) }
  end

  def test_minus
    assert_equal(0.0, 2.0.send(:-, 2))
    assert_equal(0.0, 2.0.send(:-, (2**32).coerce(2).first))
    assert_equal(0.0, 2.0.send(:-, 2.0))
    assert_raise(TypeError) { 2.0.send(:-, nil) }
  end

  def test_mul
    assert_equal(4.0, 2.0.send(:*, 2))
    assert_equal(4.0, 2.0.send(:*, (2**32).coerce(2).first))
    assert_equal(4.0, 2.0.send(:*, 2.0))
    assert_raise(TypeError) { 2.0.send(:*, nil) }
  end

  def test_div2
    assert_equal(1.0, 2.0.send(:/, 2))
    assert_equal(1.0, 2.0.send(:/, (2**32).coerce(2).first))
    assert_equal(1.0, 2.0.send(:/, 2.0))
    assert_raise(TypeError) { 2.0.send(:/, nil) }
  end

  def test_modulo2
    assert_equal(0.0, 2.0.send(:%, 2))
    assert_equal(0.0, 2.0.send(:%, (2**32).coerce(2).first))
    assert_equal(0.0, 2.0.send(:%, 2.0))
    assert_raise(TypeError) { 2.0.send(:%, nil) }
  end

  def test_divmod2
    assert_equal([1.0, 0.0], 2.0.divmod(2))
    assert_equal([1.0, 0.0], 2.0.divmod((2**32).coerce(2).first))
    assert_equal([1.0, 0.0], 2.0.divmod(2.0))
    assert_raise(TypeError) { 2.0.divmod(nil) }

    inf = 1.0 / 0.0
    a, b = inf.divmod(0)
    assert(a.infinite?)
    assert(b.nan?)

    a, b = (2.0**32).divmod(1.0)
    assert_equal(2**32, a)
    assert_equal(0, b)
  end

  def test_pow
    assert_equal(1.0, 1.0 ** (2**32))
    assert_equal(1.0, 1.0 ** 1.0)
    assert_raise(TypeError) { 1.0 ** nil }
  end

  def test_eql
    inf = 1.0 / 0.0
    nan = inf / inf
    assert(1.0.eql?(1.0))
    assert(inf.eql?(inf))
    assert(!(nan.eql?(nan)))
    assert(!(1.0.eql?(nil)))

    assert(1.0 == 1)
    assert(1.0 != 2**32)
    assert(1.0 != nan)
    assert(1.0 != nil)
  end

  def test_cmp
    inf = 1.0 / 0.0
    nan = inf / inf
    assert_equal(0, 1.0 <=> 1.0)
    assert_equal(1, 1.0 <=> 0.0)
    assert_equal(-1, 1.0 <=> 2.0)
    assert_nil(1.0 <=> nil)
    assert_nil(1.0 <=> nan)
    assert_nil(nan <=> 1.0)

    assert_equal(0, 1.0 <=> 1)
    assert_equal(1, 1.0 <=> 0)
    assert_equal(-1, 1.0 <=> 2)

    assert_equal(-1, 1.0 <=> 2**32)

    assert_raise(ArgumentError) { 1.0 > nil }
    assert_raise(ArgumentError) { 1.0 >= nil }
    assert_raise(ArgumentError) { 1.0 < nil }
    assert_raise(ArgumentError) { 1.0 <= nil }
  end

  def test_zero_p
    assert(0.0.zero?)
    assert(!(1.0.zero?))
  end

  def test_infinite_p
    inf = 1.0 / 0.0
    assert(1, inf.infinite?)
    assert(1, (-inf).infinite?)
    assert_nil(1.0.infinite?)
  end

  def test_finite_p
    inf = 1.0 / 0.0
    assert(!(inf.finite?))
    assert(!((-inf).finite?))
    assert(1.0.finite?)
  end

  def test_floor_ceil_round_truncate
    assert_equal(1, 1.5.floor)
    assert_equal(2, 1.5.ceil)
    assert_equal(2, 1.5.round)
    assert_equal(1, 1.5.truncate)

    assert_equal(2, 2.0.floor)
    assert_equal(2, 2.0.ceil)
    assert_equal(2, 2.0.round)
    assert_equal(2, 2.0.truncate)

    assert_equal(-2, (-1.5).floor)
    assert_equal(-1, (-1.5).ceil)
    assert_equal(-2, (-1.5).round)
    assert_equal(-1, (-1.5).truncate)

    assert_equal(-2, (-2.0).floor)
    assert_equal(-2, (-2.0).ceil)
    assert_equal(-2, (-2.0).round)
    assert_equal(-2, (-2.0).truncate)

    inf = 1.0/0.0
    assert_raise(FloatDomainError) { inf.floor }
    assert_raise(FloatDomainError) { inf.ceil }
    assert_raise(FloatDomainError) { inf.round }
    assert_raise(FloatDomainError) { inf.truncate }

    assert_equal(1.100, 1.111.round(1))
    assert_equal(1.110, 1.111.round(2))
    assert_equal(11110.0, 11111.1.round(-1))
    assert_equal(11100.0, 11111.1.round(-2))
  end

  def test_induced_from
    assert_equal(1.0, Float.induced_from(1))
    assert_equal(1.0, Float.induced_from(1.0))
    assert_raise(TypeError) { Float.induced_from(nil) }
  end
end
