require_relative "testbase"

class TestBigDecimal < Test::Unit::TestCase
  include TestBigDecimalBase

  def test_version
    assert_equal("1.0.1", BigDecimal.ver)
  end

  def test_global_new
    assert_equal(1, BigDecimal("1"))
    assert_equal(1, BigDecimal("1", 1))
    assert_raise(ArgumentError) { BigDecimal("1", -1) }
  end

  def test_new
    assert_equal(1, BigDecimal.new("1"))
    assert_equal(1, BigDecimal.new("1", 1))
    assert_equal(1, BigDecimal.new(" 1 "))
    assert_equal(111, BigDecimal.new("1_1_1_"))
    assert_equal(0, BigDecimal.new("_1_1_1"))

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_equal( 1, BigDecimal.new("Infinity").infinite?)
    assert_equal(-1, BigDecimal.new("-Infinity").infinite?)
    assert_equal(true, BigDecimal.new("NaN").nan?)
    assert_equal( 1, BigDecimal.new("1E11111111111").infinite?)
  end

  def _test_mode(type)
    BigDecimal.mode(type, true)
    assert_raise(FloatDomainError) { yield }

    BigDecimal.mode(type, false)
    assert_nothing_raised { yield }
  end

  def test_mode
    assert_raise(TypeError) { BigDecimal.mode(BigDecimal::EXCEPTION_ALL, 1) }
    assert_raise(TypeError) { BigDecimal.mode(BigDecimal::ROUND_MODE, 256) }
    assert_raise(TypeError) { BigDecimal.mode(0xf000, true) }
  end

  def test_exception_nan
    _test_mode(BigDecimal::EXCEPTION_NaN) { BigDecimal.new("NaN") }
  end

  def test_exception_infinity
    _test_mode(BigDecimal::EXCEPTION_INFINITY) { BigDecimal.new("Infinity") }
  end

  def test_exception_underflow
    _test_mode(BigDecimal::EXCEPTION_UNDERFLOW) do
      x = BigDecimal.new("0.1")
      100.times do
        x *= x
      end
    end
  end

  def test_exception_overflow
    _test_mode(BigDecimal::EXCEPTION_OVERFLOW) do
      x = BigDecimal.new("10")
      100.times do
        x *= x
      end
    end
  end

  def test_exception_zerodivide
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    _test_mode(BigDecimal::EXCEPTION_ZERODIVIDE) { 1 / BigDecimal.new("0") }
    _test_mode(BigDecimal::EXCEPTION_ZERODIVIDE) { -1 / BigDecimal.new("0") }
  end

  def test_round_up
    n4 = BigDecimal.new("4") # n4 / 9 = 0.44444...
    n5 = BigDecimal.new("5") # n5 / 9 = 0.55555...
    n6 = BigDecimal.new("6") # n6 / 9 = 0.66666...
    m4, m5, m6 = -n4, -n5, -n6
    n2h = BigDecimal.new("2.5")
    n3h = BigDecimal.new("3.5")
    m2h, m3h = -n2h, -n3h

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_UP)
    assert_operator(n4, :<, n4 / 9 * 9)
    assert_operator(n5, :<, n5 / 9 * 9)
    assert_operator(n6, :<, n6 / 9 * 9)
    assert_operator(m4, :>, m4 / 9 * 9)
    assert_operator(m5, :>, m5 / 9 * 9)
    assert_operator(m6, :>, m6 / 9 * 9)
    assert_equal(3, n2h.round)
    assert_equal(4, n3h.round)
    assert_equal(-3, m2h.round)
    assert_equal(-4, m3h.round)

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_DOWN)
    assert_operator(n4, :>, n4 / 9 * 9)
    assert_operator(n5, :>, n5 / 9 * 9)
    assert_operator(n6, :>, n6 / 9 * 9)
    assert_operator(m4, :<, m4 / 9 * 9)
    assert_operator(m5, :<, m5 / 9 * 9)
    assert_operator(m6, :<, m6 / 9 * 9)
    assert_equal(2, n2h.round)
    assert_equal(3, n3h.round)
    assert_equal(-2, m2h.round)
    assert_equal(-3, m3h.round)

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_UP)
    assert_operator(n4, :>, n4 / 9 * 9)
    assert_operator(n5, :<, n5 / 9 * 9)
    assert_operator(n6, :<, n6 / 9 * 9)
    assert_operator(m4, :<, m4 / 9 * 9)
    assert_operator(m5, :>, m5 / 9 * 9)
    assert_operator(m6, :>, m6 / 9 * 9)
    assert_equal(3, n2h.round)
    assert_equal(4, n3h.round)
    assert_equal(-3, m2h.round)
    assert_equal(-4, m3h.round)

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_DOWN)
    assert_operator(n4, :>, n4 / 9 * 9)
    assert_operator(n5, :>, n5 / 9 * 9)
    assert_operator(n6, :<, n6 / 9 * 9)
    assert_operator(m4, :<, m4 / 9 * 9)
    assert_operator(m5, :<, m5 / 9 * 9)
    assert_operator(m6, :>, m6 / 9 * 9)
    assert_equal(2, n2h.round)
    assert_equal(3, n3h.round)
    assert_equal(-2, m2h.round)
    assert_equal(-3, m3h.round)

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)
    assert_operator(n4, :>, n4 / 9 * 9)
    assert_operator(n5, :<, n5 / 9 * 9)
    assert_operator(n6, :<, n6 / 9 * 9)
    assert_operator(m4, :<, m4 / 9 * 9)
    assert_operator(m5, :>, m5 / 9 * 9)
    assert_operator(m6, :>, m6 / 9 * 9)
    assert_equal(2, n2h.round)
    assert_equal(4, n3h.round)
    assert_equal(-2, m2h.round)
    assert_equal(-4, m3h.round)

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_CEILING)
    assert_operator(n4, :<, n4 / 9 * 9)
    assert_operator(n5, :<, n5 / 9 * 9)
    assert_operator(n6, :<, n6 / 9 * 9)
    assert_operator(m4, :<, m4 / 9 * 9)
    assert_operator(m5, :<, m5 / 9 * 9)
    assert_operator(m6, :<, m6 / 9 * 9)
    assert_equal(3, n2h.round)
    assert_equal(4, n3h.round)
    assert_equal(-2, m2h.round)
    assert_equal(-3, m3h.round)

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_FLOOR)
    assert_operator(n4, :>, n4 / 9 * 9)
    assert_operator(n5, :>, n5 / 9 * 9)
    assert_operator(n6, :>, n6 / 9 * 9)
    assert_operator(m4, :>, m4 / 9 * 9)
    assert_operator(m5, :>, m5 / 9 * 9)
    assert_operator(m6, :>, m6 / 9 * 9)
    assert_equal(2, n2h.round)
    assert_equal(3, n3h.round)
    assert_equal(-3, m2h.round)
    assert_equal(-4, m3h.round)
  end

  def test_zero_p
    assert_equal(true, BigDecimal.new("0").zero?)
    assert_equal(false, BigDecimal.new("1").zero?)
    assert_equal(true, BigDecimal.new("0E200000000000000").zero?)
  end

  def test_nonzero_p
    assert_equal(nil, BigDecimal.new("0").nonzero?)
    assert_equal(BigDecimal.new("1"), BigDecimal.new("1").nonzero?)
  end

  def test_double_fig
    assert_kind_of(Integer, BigDecimal.double_fig)
  end

  def test_cmp
    n1 = BigDecimal.new("1")
    n2 = BigDecimal.new("2")
    assert_equal( 0, n1 <=> n1)
    assert_equal( 1, n2 <=> n1)
    assert_equal(-1, n1 <=> n2)
    assert_operator(n1, :==, n1)
    assert_operator(n1, :!=, n2)
    assert_operator(n1, :<, n2)
    assert_operator(n1, :<=, n1)
    assert_operator(n1, :<=, n2)
    assert_operator(n2, :>, n1)
    assert_operator(n2, :>=, n1)
    assert_operator(n1, :>=, n1)

    assert_operator(BigDecimal.new("-0"), :==, BigDecimal.new("0"))
    assert_operator(BigDecimal.new("0"), :<, BigDecimal.new("1"))
    assert_operator(BigDecimal.new("1"), :>, BigDecimal.new("0"))
    assert_operator(BigDecimal.new("1"), :>, BigDecimal.new("-1"))
    assert_operator(BigDecimal.new("-1"), :<, BigDecimal.new("1"))
    assert_operator(BigDecimal.new((2**100).to_s), :>, BigDecimal.new("1"))
    assert_operator(BigDecimal.new("1"), :<, BigDecimal.new((2**100).to_s))

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    inf = BigDecimal.new("Infinity")
    assert_operator(inf, :>, 1)
    assert_operator(1, :<, inf)
  end

  def test_cmp_nan
    n1 = BigDecimal.new("1")
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_equal(nil, BigDecimal.new("NaN") <=> n1)
    assert_equal(false, BigDecimal.new("NaN") > n1)
  end

  def test_cmp_failing_coercion
    n1 = BigDecimal.new("1")
    assert_equal(nil, n1 <=> nil)
    assert_raise(ArgumentError){n1 > nil}
  end

  def test_cmp_coerce
    n1 = BigDecimal.new("1")
    n2 = BigDecimal.new("2")
    o1 = Object.new; def o1.coerce(x); [x, BigDecimal.new("1")]; end
    o2 = Object.new; def o2.coerce(x); [x, BigDecimal.new("2")]; end
    assert_equal( 0, n1 <=> o1)
    assert_equal( 1, n2 <=> o1)
    assert_equal(-1, n1 <=> o2)
    assert_operator(n1, :==, o1)
    assert_operator(n1, :!=, o2)
    assert_operator(n1, :<, o2)
    assert_operator(n1, :<=, o1)
    assert_operator(n1, :<=, o2)
    assert_operator(n2, :>, o1)
    assert_operator(n2, :>=, o1)
    assert_operator(n1, :>=, 1)
  end

  def test_cmp_bignum
    assert_operator(BigDecimal.new((2**100).to_s), :==, 2**100)
  end

  def test_cmp_data
    d = Time.now; def d.coerce(x); [x, x]; end
    assert_operator(BigDecimal.new((2**100).to_s), :==, d)
  end

  def test_precs
    a = BigDecimal.new("1").precs
    assert_instance_of(Array, a)
    assert_equal(2, a.size)
    assert_kind_of(Integer, a[0])
    assert_kind_of(Integer, a[1])
  end

  def test_hash
    a = []
    b = BigDecimal.new("1")
    10.times { a << b *= 10 }
    h = {}
    a.each_with_index {|x, i| h[x] = i }
    a.each_with_index do |x, i|
      assert_equal(i, h[x])
    end
  end

  def test_marshal
    s = Marshal.dump(BigDecimal("1", 1))
    assert_equal(BigDecimal("1", 1), Marshal.load(s))

    # corrupt data
    s = s.gsub(/BigDecimal.*\z/m) {|x| x.gsub(/\d/m, "-") }
    assert_raise(TypeError) { Marshal.load(s) }
  end

  def test_finite_infinite_nan
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)

    x = BigDecimal.new("0")
    assert_equal(true, x.finite?)
    assert_equal(nil, x.infinite?)
    assert_equal(false, x.nan?)
    y = 1 / x
    assert_equal(false, y.finite?)
    assert_equal(1, y.infinite?)
    assert_equal(false, y.nan?)
    y = -1 / x
    assert_equal(false, y.finite?)
    assert_equal(-1, y.infinite?)
    assert_equal(false, y.nan?)

    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    y = 0 / x
    assert_equal(false, y.finite?)
    assert_equal(nil, y.infinite?)
    assert_equal(true, y.nan?)
  end

  def test_to_i
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)

    x = BigDecimal.new("0")
    assert_kind_of(Integer, x.to_i)
    assert_equal(0, x.to_i)
    assert_raise(FloatDomainError){( 1 / x).to_i}
    assert_raise(FloatDomainError){(-1 / x).to_i}
    assert_raise(FloatDomainError) {( 0 / x).to_i}
    x = BigDecimal.new("1")
    assert_equal(1, x.to_i)
    x = BigDecimal.new((2**100).to_s)
    assert_equal(2**100, x.to_i)
  end

  def test_to_f
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)

    x = BigDecimal.new("0")
    assert_instance_of(Float, x.to_f)
    assert_equal(0.0, x.to_f)
    assert_equal( 1.0 / 0.0, ( 1 / x).to_f)
    assert_equal(-1.0 / 0.0, (-1 / x).to_f)
    assert_equal(true, ( 0 / x).to_f.nan?)
    x = BigDecimal.new("1")
    assert_equal(1.0, x.to_f)
    x = BigDecimal.new((2**100).to_s)
    assert_equal((2**100).to_f, x.to_f)
    x = BigDecimal.new("1" + "0" * 10000)
    assert_equal(0, BigDecimal.new("-0").to_f)

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, true)
    assert_raise(FloatDomainError) { x.to_f }
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    assert_kind_of(Float,   x .to_f)
    assert_kind_of(Float, (-x).to_f)
  end

  def test_coerce
    a, b = BigDecimal.new("1").coerce(1.0)
    assert_instance_of(Float, a)
    assert_instance_of(Float, b)
    assert_equal(2, 1 + BigDecimal.new("1"), '[ruby-core:25697]')
  end

  def test_uplus
    x = BigDecimal.new("1")
    assert_equal(x, x.send(:+@))
  end

  def test_add
    x = BigDecimal.new("1")
    assert_equal(BigDecimal.new("2"), x + x)
    assert_equal(1, BigDecimal.new("0") + 1)
    assert_equal(1, x + 0)

    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("0") + 0).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("-0") + 0).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (BigDecimal.new("-0") + BigDecimal.new("-0")).sign)

    x = BigDecimal.new((2**100).to_s)
    assert_equal(BigDecimal.new((2**100+1).to_s), x + 1)
  end

  def test_sub
    x = BigDecimal.new("1")
    assert_equal(BigDecimal.new("0"), x - x)
    assert_equal(-1, BigDecimal.new("0") - 1)
    assert_equal(1, x - 0)

    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("0") - 0).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (BigDecimal.new("-0") - 0).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("-0") - BigDecimal.new("-0")).sign)

    x = BigDecimal.new((2**100).to_s)
    assert_equal(BigDecimal.new((2**100-1).to_s), x - 1)
  end

  def test_mult
    x = BigDecimal.new((2**100).to_s)
    assert_equal(BigDecimal.new((2**100 * 3).to_s), (x * 3).to_i)
    assert_equal(x, (x * 1).to_i)
    assert_equal(x, (BigDecimal("1") * x).to_i)
    assert_equal(BigDecimal.new((2**200).to_s), (x * x).to_i)
  end

  def test_div
    x = BigDecimal.new((2**100).to_s)
    assert_equal(BigDecimal.new((2**100 / 3).to_s), (x / 3).to_i)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("0") / 1).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (BigDecimal.new("-0") / 1).sign)
    assert_equal(2, BigDecimal.new("2") / 1)
    assert_equal(-2, BigDecimal.new("2") / -1)
  end

  def test_mod
    x = BigDecimal.new((2**100).to_s)
    assert_equal(1, x % 3)
    assert_equal(2, (-x) % 3)
    assert_equal(-2, x % -3)
    assert_equal(-1, (-x) % -3)
  end

  def test_remainder
    x = BigDecimal.new((2**100).to_s)
    assert_equal(1, x.remainder(3))
    assert_equal(-1, (-x).remainder(3))
    assert_equal(1, x.remainder(-3))
    assert_equal(-1, (-x).remainder(-3))
  end

  def test_divmod
    x = BigDecimal.new((2**100).to_s)
    assert_equal([(x / 3).floor, 1], x.divmod(3))
    assert_equal([(-x / 3).floor, 2], (-x).divmod(3))

    assert_equal([0, 0], BigDecimal.new("0").divmod(2))

    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_raise(ZeroDivisionError){BigDecimal.new("0").divmod(0)}
  end

  def test_add_bigdecimal
    x = BigDecimal.new((2**100).to_s)
    assert_equal(3000000000000000000000000000000, x.add(x, 1))
    assert_equal(2500000000000000000000000000000, x.add(x, 2))
    assert_equal(2540000000000000000000000000000, x.add(x, 3))
  end

  def test_sub_bigdecimal
    x = BigDecimal.new((2**100).to_s)
    assert_equal(1000000000000000000000000000000, x.sub(1, 1))
    assert_equal(1300000000000000000000000000000, x.sub(1, 2))
    assert_equal(1270000000000000000000000000000, x.sub(1, 3))
  end

  def test_mult_bigdecimal
    x = BigDecimal.new((2**100).to_s)
    assert_equal(4000000000000000000000000000000, x.mult(3, 1))
    assert_equal(3800000000000000000000000000000, x.mult(3, 2))
    assert_equal(3800000000000000000000000000000, x.mult(3, 3))
  end

  def test_div_bigdecimal
    x = BigDecimal.new((2**100).to_s)
    assert_equal(422550200076076467165567735125, x.div(3))
    assert_equal(400000000000000000000000000000, x.div(3, 1))
    assert_equal(420000000000000000000000000000, x.div(3, 2))
    assert_equal(423000000000000000000000000000, x.div(3, 3))
  end

  def test_abs_bigdecimal
    x = BigDecimal.new((2**100).to_s)
    assert_equal(1267650600228229401496703205376, x.abs)
    x = BigDecimal.new("-" + (2**100).to_s)
    assert_equal(1267650600228229401496703205376, x.abs)
    x = BigDecimal.new("0")
    assert_equal(0, x.abs)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    x = BigDecimal.new("NaN")
    assert_equal(true, x.abs.nan?)
  end

  def test_sqrt_bigdecimal
    x = BigDecimal.new("0.09")
    assert_in_delta(0.3, x.sqrt(1), 0.001)
    x = BigDecimal.new((2**100).to_s)
    y = BigDecimal("1125899906842624")
    e = y.exponent
    assert_equal(true, (x.sqrt(100) - y).abs < BigDecimal("1E#{e-100}"))
    assert_equal(true, (x.sqrt(200) - y).abs < BigDecimal("1E#{e-200}"))
    assert_equal(true, (x.sqrt(300) - y).abs < BigDecimal("1E#{e-300}"))
    x = BigDecimal.new("-" + (2**100).to_s)
    assert_raise(FloatDomainError) { x.sqrt(1) }
    x = BigDecimal.new((2**200).to_s)
    assert_equal(2**100, x.sqrt(1))

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_raise(FloatDomainError) { BigDecimal.new("NaN").sqrt(1) }

    assert_equal(0, BigDecimal.new("0").sqrt(1))
    assert_equal(1, BigDecimal.new("1").sqrt(1))
  end

  def test_fix
    x = BigDecimal.new("1.1")
    assert_equal(1, x.fix)
  end

  def test_frac
    x = BigDecimal.new("1.1")
    assert_equal(0.1, x.frac)
    assert_equal(0.1, BigDecimal.new("0.1").frac)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_equal(true, BigDecimal.new("NaN").frac.nan?)
  end

  def test_round
    assert_equal(3, BigDecimal.new("3.14159").round)
    assert_equal(9, BigDecimal.new("8.7").round)
    assert_equal(3.142, BigDecimal.new("3.14159").round(3))
    assert_equal(13300.0, BigDecimal.new("13345.234").round(-2))

    x = BigDecimal.new("111.111")
    assert_equal(111    , x.round)
    assert_equal(111.1  , x.round(1))
    assert_equal(111.11 , x.round(2))
    assert_equal(111.111, x.round(3))
    assert_equal(111.111, x.round(4))
    assert_equal(110    , x.round(-1))
    assert_equal(100    , x.round(-2))
    assert_equal(  0    , x.round(-3))
    assert_equal(  0    , x.round(-4))

    x = BigDecimal.new("2.5")
    assert_equal(3, x.round(0, BigDecimal::ROUND_UP))
    assert_equal(2, x.round(0, BigDecimal::ROUND_DOWN))
    assert_equal(3, x.round(0, BigDecimal::ROUND_HALF_UP))
    assert_equal(2, x.round(0, BigDecimal::ROUND_HALF_DOWN))
    assert_equal(2, x.round(0, BigDecimal::ROUND_HALF_EVEN))
    assert_equal(3, x.round(0, BigDecimal::ROUND_CEILING))
    assert_equal(2, x.round(0, BigDecimal::ROUND_FLOOR))
    assert_raise(TypeError) { x.round(0, 256) }
  end

  def test_truncate
    assert_equal(3, BigDecimal.new("3.14159").truncate)
    assert_equal(8, BigDecimal.new("8.7").truncate)
    assert_equal(3.141, BigDecimal.new("3.14159").truncate(3))
    assert_equal(13300.0, BigDecimal.new("13345.234").truncate(-2))
  end

  def test_floor
    assert_equal(3, BigDecimal.new("3.14159").floor)
    assert_equal(-10, BigDecimal.new("-9.1").floor)
    assert_equal(3.141, BigDecimal.new("3.14159").floor(3))
    assert_equal(13300.0, BigDecimal.new("13345.234").floor(-2))
  end

  def test_ceil
    assert_equal(4, BigDecimal.new("3.14159").ceil)
    assert_equal(-9, BigDecimal.new("-9.1").ceil)
    assert_equal(3.142, BigDecimal.new("3.14159").ceil(3))
    assert_equal(13400.0, BigDecimal.new("13345.234").ceil(-2))
  end

  def test_to_s
    assert_equal('-123.45678 90123 45678 9', BigDecimal.new('-123.45678901234567890').to_s('5F'))
    assert_equal('+123.45678901 23456789', BigDecimal.new('123.45678901234567890').to_s('+8F'))
    assert_equal(' 123.4567890123456789', BigDecimal.new('123.45678901234567890').to_s(' F'))
    assert_equal('0.1234567890123456789E3', BigDecimal.new('123.45678901234567890').to_s)
    assert_equal('0.12345 67890 12345 6789E3', BigDecimal.new('123.45678901234567890').to_s(5))
  end

  def test_split
    x = BigDecimal.new('-123.45678901234567890')
    assert_equal([-1, "1234567890123456789", 10, 3], x.split)
    assert_equal([1, "0", 10, 0], BigDecimal.new("0").split)
    assert_equal([-1, "0", 10, 0], BigDecimal.new("-0").split)

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_equal([0, "NaN", 10, 0], BigDecimal.new("NaN").split)
    assert_equal([1, "Infinity", 10, 0], BigDecimal.new("Infinity").split)
    assert_equal([-1, "Infinity", 10, 0], BigDecimal.new("-Infinity").split)
  end

  def test_exponent
    x = BigDecimal.new('-123.45678901234567890')
    assert_equal(3, x.exponent)
  end

  def test_inspect
    x = BigDecimal.new("1234.5678")
    prec, maxprec = x.precs
    assert_match(/^#<BigDecimal:[0-9a-f]+,'0.12345678E4',#{prec}\(#{maxprec}\)>$/, x.inspect)
  end

  def test_power
    x = BigDecimal.new("3")
    assert_equal(81, x ** 4)
    assert_equal(1.0/81, x ** -4)
    assert_equal(1, x ** 0)
    assert_raise(TypeError) { x ** x }
    assert_equal(0, BigDecimal.new("0") ** 4)
    assert_equal(1, BigDecimal.new("0") ** 0)
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    assert_equal(BigDecimal.new("Infinity"), BigDecimal.new("0") ** -1)
    assert_equal(BigDecimal.new("-Infinity"), BigDecimal.new("-0") ** -1)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_equal(true, (BigDecimal.new("NaN") ** 1).nan?)

    assert_equal(BigDecimal::SIGN_POSITIVE_INFINITE, (BigDecimal.new("Infinity") ** 2).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_INFINITE, (BigDecimal.new("Infinity") ** 1).sign)
    assert_equal(1, BigDecimal.new("Infinity") ** 0)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("Infinity") ** -1).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("Infinity") ** -2).sign)

    assert_equal(BigDecimal::SIGN_POSITIVE_INFINITE, (BigDecimal.new("-Infinity") ** 2).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_INFINITE, (BigDecimal.new("-Infinity") ** 1).sign)
    assert_equal(1, BigDecimal.new("-Infinity") ** 0)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (BigDecimal.new("-Infinity") ** -1).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal.new("-Infinity") ** -2).sign)
  end

  def test_limit
    BigDecimal.limit(1)
    x = BigDecimal.new("3")
    assert_equal(90, x ** 4) # OK? must it be 80?
    # 3 * 3 * 3 * 3 = 10 * 3 * 3 = 30 * 3 = 90 ???
    assert_raise(ArgumentError) { BigDecimal.limit(-1) }
  end

  def test_sign
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)

    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, BigDecimal.new("0").sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, BigDecimal.new("-0").sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_FINITE, BigDecimal.new("1").sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_FINITE, BigDecimal.new("-1").sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_INFINITE, (BigDecimal.new("1") / 0).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_INFINITE, (BigDecimal.new("-1") / 0).sign)
    assert_equal(BigDecimal::SIGN_NaN, (BigDecimal.new("0") / 0).sign)
  end

  def test_inf
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    inf = BigDecimal.new("Infinity")

    assert_equal(inf, inf + inf)
    assert_equal(true, (inf + (-inf)).nan?)
    assert_equal(true, (inf - inf).nan?)
    assert_equal(inf, inf - (-inf))
    assert_equal(inf, inf * inf)
    assert_equal(true, (inf / inf).nan?)

    assert_equal(inf, inf + 1)
    assert_equal(inf, inf - 1)
    assert_equal(inf, inf * 1)
    assert_equal(true, (inf * 0).nan?)
    assert_equal(inf, inf / 1)

    assert_equal(inf, 1 + inf)
    assert_equal(-inf, 1 - inf)
    assert_equal(inf, 1 * inf)
    assert_equal(-inf, -1 * inf)
    assert_equal(true, (0 * inf).nan?)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (1 / inf).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (-1 / inf).sign)
  end

  def test_to_special_string
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    nan = BigDecimal.new("NaN")
    assert_equal("NaN", nan.to_s)
    inf = BigDecimal.new("Infinity")
    assert_equal("Infinity", inf.to_s)
    assert_equal(" Infinity", inf.to_s(" "))
    assert_equal("+Infinity", inf.to_s("+"))
    assert_equal("-Infinity", (-inf).to_s)
    pzero = BigDecimal.new("0")
    assert_equal("0.0", pzero.to_s)
    assert_equal(" 0.0", pzero.to_s(" "))
    assert_equal("+0.0", pzero.to_s("+"))
    assert_equal("-0.0", (-pzero).to_s)
  end

  def test_to_string
    assert_equal("0.01", BigDecimal("0.01").to_s("F"))
    s = "0." + "0" * 100 + "1"
    assert_equal(s, BigDecimal(s).to_s("F"))
    s = "1" + "0" * 100 + ".0"
    assert_equal(s, BigDecimal(s).to_s("F"))
  end

  def test_ctov
    assert_equal(0.1, BigDecimal.new("1E-1"))
    assert_equal(10, BigDecimal.new("1E+1"))
    assert_equal(1, BigDecimal.new("+1"))
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)

    assert_equal(BigDecimal::SIGN_POSITIVE_INFINITE, BigDecimal.new("1E1" + "0" * 10000).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_INFINITE, BigDecimal.new("-1E1" + "0" * 10000).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, BigDecimal.new("1E-1" + "0" * 10000).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, BigDecimal.new("-1E-1" + "0" * 10000).sign)
  end

  def test_gc
    bug3258 = '[ruby-dev:41213]'
    stress, GC.stress = GC.stress, true
    10.upto(20) do |i|
      b = BigDecimal.new("1"+"0"*i)
      assert_equal([1, "1", 10, i+1], b.split, bug3258)
    end
  ensure
    GC.stress = stress
  end
end
