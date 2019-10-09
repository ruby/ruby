# frozen_string_literal: false
require_relative "testbase"
require 'bigdecimal/math'

class TestBigDecimal < Test::Unit::TestCase
  include TestBigDecimalBase

  ROUNDING_MODE_MAP = [
    [ BigDecimal::ROUND_UP,        :up],
    [ BigDecimal::ROUND_DOWN,      :down],
    [ BigDecimal::ROUND_DOWN,      :truncate],
    [ BigDecimal::ROUND_HALF_UP,   :half_up],
    [ BigDecimal::ROUND_HALF_UP,   :default],
    [ BigDecimal::ROUND_HALF_DOWN, :half_down],
    [ BigDecimal::ROUND_HALF_EVEN, :half_even],
    [ BigDecimal::ROUND_HALF_EVEN, :banker],
    [ BigDecimal::ROUND_CEILING,   :ceiling],
    [ BigDecimal::ROUND_CEILING,   :ceil],
    [ BigDecimal::ROUND_FLOOR,     :floor],
  ]

  def assert_nan(x)
    assert(x.nan?, "Expected #{x.inspect} to be NaN")
  end

  def assert_positive_infinite(x)
    assert(x.infinite?, "Expected #{x.inspect} to be positive infinite")
    assert_operator(x, :>, 0)
  end

  def assert_negative_infinite(x)
    assert(x.infinite?, "Expected #{x.inspect} to be negative infinite")
    assert_operator(x, :<, 0)
  end

  def assert_positive_zero(x)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, x.sign,
                 "Expected #{x.inspect} to be positive zero")
  end

  def assert_negative_zero(x)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, x.sign,
                 "Expected #{x.inspect} to be negative zero")
  end

  def test_not_equal
    assert_not_equal BigDecimal("1"), BigDecimal("2")
  end

  def test_BigDecimal
    assert_equal(1, BigDecimal("1"))
    assert_equal(1, BigDecimal("1", 1))
    assert_equal(1, BigDecimal(" 1 "))
    assert_equal(111, BigDecimal("1_1_1_"))
    assert_equal(10**(-1), BigDecimal("1E-1"), '#4825')
    assert_equal(1234, BigDecimal(" \t\n\r \r1234 \t\n\r \r"))

    assert_raise(ArgumentError) { BigDecimal("1", -1) }
    assert_raise_with_message(ArgumentError, /"1__1_1"/) { BigDecimal("1__1_1") }
    assert_raise_with_message(ArgumentError, /"_1_1_1"/) { BigDecimal("_1_1_1") }

    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_positive_infinite(BigDecimal("Infinity"))
      assert_positive_infinite(BigDecimal("1E1111111111111111111"))
      assert_positive_infinite(BigDecimal(" \t\n\r \rInfinity \t\n\r \r"))
      assert_negative_infinite(BigDecimal("-Infinity"))
      assert_negative_infinite(BigDecimal(" \t\n\r \r-Infinity \t\n\r \r"))
      assert_nan(BigDecimal("NaN"))
      assert_nan(BigDecimal(" \t\n\r \rNaN \t\n\r \r"))
    end
  end

  def test_BigDecimal_bug7522
    bd = BigDecimal("1.12", 1)
    assert_same(bd, BigDecimal(bd))
    assert_same(bd, BigDecimal(bd, exception: false))
    assert_not_same(bd, BigDecimal(bd, 1))
    assert_not_same(bd, BigDecimal(bd, 1, exception: false))
  end

  def test_BigDecimal_with_invalid_string
    [
      '', '.', 'e1', 'd1', '.e', '.d', '1.e', '1.d', '.1e', '.1d',
      '2,30', '19,000.0', '-2,30', '-19,000.0', '+2,30', '+19,000.0',
      '2.3,0', '19.000,0', '-2.3,0', '-19.000,0', '+2.3,0', '+19.000,0',
      '2.3.0', '19.000.0', '-2.3.0', '-19.000.0', '+2.3.0', '+19.000.0',
      'invlaid value', '123 xyz'
    ].each do |invalid_string|
      assert_raise_with_message(ArgumentError, %Q[invalid value for BigDecimal(): "#{invalid_string}"]) do
        BigDecimal(invalid_string)
      end
    end

    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_raise_with_message(ArgumentError, /"Infinity_"/) { BigDecimal("Infinity_") }
      assert_raise_with_message(ArgumentError, /"\+Infinity_"/) { BigDecimal("+Infinity_") }
      assert_raise_with_message(ArgumentError, /"-Infinity_"/) { BigDecimal("-Infinity_") }
      assert_raise_with_message(ArgumentError, /"NaN_"/) { BigDecimal("NaN_") }
    end
  end

  def test_BigDecimal_with_integer
    assert_equal(BigDecimal("1"), BigDecimal(1))
    assert_equal(BigDecimal("-1"), BigDecimal(-1))
    assert_equal(BigDecimal((2**100).to_s), BigDecimal(2**100))
    assert_equal(BigDecimal((-2**100).to_s), BigDecimal(-2**100))
  end

  def test_BigDecimal_with_rational
    assert_equal(BigDecimal("0.333333333333333333333"), BigDecimal(1.quo(3), 21))
    assert_equal(BigDecimal("-0.333333333333333333333"), BigDecimal(-1.quo(3), 21))
    assert_raise_with_message(ArgumentError, "can't omit precision for a Rational.") { BigDecimal(42.quo(7)) }
  end

  def test_BigDecimal_with_float
    assert_equal(BigDecimal("0.1235"), BigDecimal(0.1234567, 4))
    assert_equal(BigDecimal("-0.1235"), BigDecimal(-0.1234567, 4))
    assert_raise_with_message(ArgumentError, "can't omit precision for a Float.") { BigDecimal(4.2) }
    assert_raise(ArgumentError) { BigDecimal(0.1, Float::DIG + 2) }
    assert_nothing_raised { BigDecimal(0.1, Float::DIG + 1) }

    bug9214 = '[ruby-core:58858]'
    assert_equal(BigDecimal(-0.0, Float::DIG).sign, -1, bug9214)

    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_nan(BigDecimal(Float::NAN))
    end
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      assert_positive_infinite(BigDecimal(Float::INFINITY))
      assert_negative_infinite(BigDecimal(-Float::INFINITY))
    end
  end

  def test_BigDecimal_with_complex
    assert_equal(BigDecimal("1"), BigDecimal(Complex(1, 0)))
    assert_equal(BigDecimal("0.333333333333333333333"), BigDecimal(Complex(1.quo(3), 0), 21))
    assert_equal(BigDecimal("0.1235"), BigDecimal(Complex(0.1234567, 0), 4))

    assert_raise_with_message(ArgumentError, "Unable to make a BigDecimal from non-zero imaginary number") { BigDecimal(Complex(1, 1)) }
  end

  def test_BigDecimal_with_big_decimal
    assert_equal(BigDecimal(1), BigDecimal(BigDecimal(1)))
    assert_equal(BigDecimal('+0'), BigDecimal(BigDecimal('+0')))
    assert_equal(BigDecimal('-0'), BigDecimal(BigDecimal('-0')))
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_positive_infinite(BigDecimal(BigDecimal('Infinity')))
      assert_negative_infinite(BigDecimal(BigDecimal('-Infinity')))
      assert_nan(BigDecimal(BigDecimal('NaN')))
    end
  end

  if RUBY_VERSION < '2.7'
    def test_BigDecimal_with_tainted_string
      Thread.new {
        $SAFE = 1
        BigDecimal('1'.taint)
      }.join
    ensure
      $SAFE = 0
    end
  end

  def test_BigDecimal_with_exception_keyword
    assert_raise(ArgumentError) {
      BigDecimal('.', exception: true)
    }
    assert_nothing_raised(ArgumentError) {
      assert_equal(nil, BigDecimal(".", exception: false))
    }
    assert_raise(ArgumentError) {
      BigDecimal("1", -1, exception: true)
    }
    assert_nothing_raised(ArgumentError) {
      assert_equal(nil, BigDecimal("1", -1, exception: false))
    }
    assert_raise(ArgumentError) {
      BigDecimal(42.quo(7), exception: true)
    }
    assert_nothing_raised(ArgumentError) {
      assert_equal(nil, BigDecimal(42.quo(7), exception: false))
    }
    assert_raise(ArgumentError) {
      BigDecimal(4.2, exception: true)
    }
    assert_nothing_raised(ArgumentError) {
      assert_equal(nil, BigDecimal(4.2, exception: false))
    }
    # TODO: support conversion from complex
    # assert_raise(RangeError) {
    #   BigDecimal(1i, exception: true)
    # }
    # assert_nothing_raised(RangeError) {
    #   assert_equal(nil, BigDecimal(1i, exception: false))
    # }
    assert_raise(TypeError) {
      BigDecimal(nil, exception: true)
    }
    assert_nothing_raised(TypeError) {
      assert_equal(nil, BigDecimal(nil, exception: false))
    }
    assert_nothing_raised(TypeError) {
      assert_equal(nil, BigDecimal(:test, exception: false))
    }
    assert_nothing_raised(TypeError) {
      assert_equal(nil, BigDecimal(Object.new, exception: false))
    }
    # TODO: support to_d
    # assert_nothing_raised(TypeError) {
    #   o = Object.new
    #   def o.to_d; 3.14; end
    #   assert_equal(3.14, BigDecimal(o, exception: false))
    # }
    # assert_nothing_raised(RuntimeError) {
    #   o = Object.new
    #   def o.to_d; raise; end
    #   assert_equal(nil, BigDecimal(o, exception: false))
    # }
  end

  def test_s_ver
    assert_raise_with_message(NoMethodError, /undefined method `ver'/) { BigDecimal.ver }
  end

  def test_s_allocate
    assert_raise_with_message(NoMethodError, /undefined method `allocate'/) { BigDecimal.allocate }
  end

  def test_s_new
    assert_raise_with_message(NoMethodError, /undefined method `new'/) { BigDecimal.new("1") }
  end

  def test_s_interpret_loosely
    assert_equal(BigDecimal('1'), BigDecimal.interpret_loosely("1__1_1"))
    assert_equal(BigDecimal('2.5'), BigDecimal.interpret_loosely("2.5"))
    assert_equal(BigDecimal('2.5'), BigDecimal.interpret_loosely("2.5 degrees"))
    assert_equal(BigDecimal('2.5e1'), BigDecimal.interpret_loosely("2.5e1 degrees"))
    assert_equal(BigDecimal('0'), BigDecimal.interpret_loosely("degrees 100.0"))
    assert_equal(BigDecimal('0.125'), BigDecimal.interpret_loosely("0.1_2_5"))
    assert_equal(BigDecimal('0.125'), BigDecimal.interpret_loosely("0.1_2_5__"))
    assert_equal(BigDecimal('1'), BigDecimal.interpret_loosely("1_.125"))
    assert_equal(BigDecimal('1'), BigDecimal.interpret_loosely("1._125"))
    assert_equal(BigDecimal('0.1'), BigDecimal.interpret_loosely("0.1__2_5"))
    assert_equal(BigDecimal('0.1'), BigDecimal.interpret_loosely("0.1_e10"))
    assert_equal(BigDecimal('0.1'), BigDecimal.interpret_loosely("0.1e_10"))
    assert_equal(BigDecimal('1'), BigDecimal.interpret_loosely("0.1e1__0"))
    assert_equal(BigDecimal('1.2'), BigDecimal.interpret_loosely("1.2.3"))
    assert_equal(BigDecimal('1'), BigDecimal.interpret_loosely("1."))
    assert_equal(BigDecimal('1'), BigDecimal.interpret_loosely("1e"))

    assert_equal(BigDecimal('0.0'), BigDecimal.interpret_loosely("invalid"))

    assert(BigDecimal.interpret_loosely("2.5").frozen?)
  end

  def _test_mode(type)
    BigDecimal.mode(type, true)
    assert_raise(FloatDomainError) { yield }

    BigDecimal.mode(type, false)
    assert_nothing_raised { yield }
  end

  def test_mode
    assert_raise(ArgumentError) { BigDecimal.mode(BigDecimal::EXCEPTION_ALL, 1) }
    assert_raise(ArgumentError) { BigDecimal.mode(BigDecimal::ROUND_MODE, 256) }
    assert_raise(ArgumentError) { BigDecimal.mode(BigDecimal::ROUND_MODE, :xyzzy) }
    assert_raise(TypeError) { BigDecimal.mode(0xf000, true) }

    begin
      saved_mode = BigDecimal.mode(BigDecimal::ROUND_MODE)

      [ BigDecimal::ROUND_UP,
        BigDecimal::ROUND_DOWN,
        BigDecimal::ROUND_HALF_UP,
        BigDecimal::ROUND_HALF_DOWN,
        BigDecimal::ROUND_CEILING,
        BigDecimal::ROUND_FLOOR,
        BigDecimal::ROUND_HALF_EVEN,
      ].each do |mode|
        BigDecimal.mode(BigDecimal::ROUND_MODE, mode)
        assert_equal(mode, BigDecimal.mode(BigDecimal::ROUND_MODE))
      end
    ensure
      BigDecimal.mode(BigDecimal::ROUND_MODE, saved_mode)
    end

    BigDecimal.save_rounding_mode do
      ROUNDING_MODE_MAP.each do |const, sym|
        BigDecimal.mode(BigDecimal::ROUND_MODE, sym)
        assert_equal(const, BigDecimal.mode(BigDecimal::ROUND_MODE))
      end
    end
  end

  def test_thread_local_mode
    begin
      saved_mode = BigDecimal.mode(BigDecimal::ROUND_MODE)

      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_UP)
      Thread.start {
        BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)
        assert_equal(BigDecimal::ROUND_HALF_EVEN, BigDecimal.mode(BigDecimal::ROUND_MODE))
      }.join
      assert_equal(BigDecimal::ROUND_UP, BigDecimal.mode(BigDecimal::ROUND_MODE))
    ensure
      BigDecimal.mode(BigDecimal::ROUND_MODE, saved_mode)
    end
  end

  def test_save_exception_mode
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    mode = BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW)
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, true)
    end
    assert_equal(mode, BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW))

    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_FLOOR)
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)
    end
    assert_equal(BigDecimal::ROUND_HALF_EVEN, BigDecimal.mode(BigDecimal::ROUND_MODE))

    assert_equal(42, BigDecimal.save_exception_mode { 42 })
  end

  def test_save_rounding_mode
    BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_FLOOR)
    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)
    end
    assert_equal(BigDecimal::ROUND_FLOOR, BigDecimal.mode(BigDecimal::ROUND_MODE))

    assert_equal(42, BigDecimal.save_rounding_mode { 42 })
  end

  def test_save_limit
    begin
      old = BigDecimal.limit
      BigDecimal.limit(100)
      BigDecimal.save_limit do
        BigDecimal.limit(200)
      end
      assert_equal(100, BigDecimal.limit);
    ensure
      BigDecimal.limit(old)
    end

    assert_equal(42, BigDecimal.save_limit { 42 })
  end

  def test_exception_nan
    _test_mode(BigDecimal::EXCEPTION_NaN) { BigDecimal("NaN") }
  end

  def test_exception_infinity
    _test_mode(BigDecimal::EXCEPTION_INFINITY) { BigDecimal("Infinity") }
  end

  def test_exception_underflow
    _test_mode(BigDecimal::EXCEPTION_UNDERFLOW) do
      x = BigDecimal("0.1")
      100.times do
        x *= x
      end
    end
  end

  def test_exception_overflow
    _test_mode(BigDecimal::EXCEPTION_OVERFLOW) do
      x = BigDecimal("10")
      100.times do
        x *= x
      end
    end
  end

  def test_exception_zerodivide
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    _test_mode(BigDecimal::EXCEPTION_ZERODIVIDE) { 1 / BigDecimal("0") }
    _test_mode(BigDecimal::EXCEPTION_ZERODIVIDE) { -1 / BigDecimal("0") }
  end

  def test_round_up
    n4 = BigDecimal("4") # n4 / 9 = 0.44444...
    n5 = BigDecimal("5") # n5 / 9 = 0.55555...
    n6 = BigDecimal("6") # n6 / 9 = 0.66666...
    m4, m5, m6 = -n4, -n5, -n6
    n2h = BigDecimal("2.5")
    n3h = BigDecimal("3.5")
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
    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)

    assert_equal(true, BigDecimal("0").zero?)
    assert_equal(true, BigDecimal("-0").zero?)
    assert_equal(false, BigDecimal("1").zero?)
    assert_equal(true, BigDecimal("0E200000000000000").zero?)
    assert_equal(false, BigDecimal("Infinity").zero?)
    assert_equal(false, BigDecimal("-Infinity").zero?)
    assert_equal(false, BigDecimal("NaN").zero?)
  end

  def test_nonzero_p
    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)

    assert_equal(nil, BigDecimal("0").nonzero?)
    assert_equal(nil, BigDecimal("-0").nonzero?)
    assert_equal(BigDecimal("1"), BigDecimal("1").nonzero?)
    assert_positive_infinite(BigDecimal("Infinity").nonzero?)
    assert_negative_infinite(BigDecimal("-Infinity").nonzero?)
    assert_nan(BigDecimal("NaN").nonzero?)
  end

  def test_double_fig
    assert_kind_of(Integer, BigDecimal.double_fig)
  end

  def test_cmp
    n1 = BigDecimal("1")
    n2 = BigDecimal("2")
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

    assert_operator(BigDecimal("-0"), :==, BigDecimal("0"))
    assert_operator(BigDecimal("0"), :<, BigDecimal("1"))
    assert_operator(BigDecimal("1"), :>, BigDecimal("0"))
    assert_operator(BigDecimal("1"), :>, BigDecimal("-1"))
    assert_operator(BigDecimal("-1"), :<, BigDecimal("1"))
    assert_operator(BigDecimal((2**100).to_s), :>, BigDecimal("1"))
    assert_operator(BigDecimal("1"), :<, BigDecimal((2**100).to_s))

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    inf = BigDecimal("Infinity")
    assert_operator(inf, :>, 1)
    assert_operator(1, :<, inf)

    assert_operator(BigDecimal("1E-1"), :==, 10**(-1), '#4825')
    assert_equal(0, BigDecimal("1E-1") <=> 10**(-1), '#4825')
  end

  def test_cmp_issue9192
    bug9192 = '[ruby-core:58756] [#9192]'
    operators = { :== => :==, :< => :>, :> => :<, :<= => :>=, :>= => :<= }
    5.upto(8) do |i|
      s = "706.0#{i}"
      d = BigDecimal(s)
      f = s.to_f
      operators.each do |op, inv|
        assert_equal(d.send(op, f), f.send(inv, d),
                     "(BigDecimal(#{s.inspect}) #{op} #{s}) and (#{s} #{inv} BigDecimal(#{s.inspect})) is different #{bug9192}")
      end
    end
  end

  def test_cmp_nan
    n1 = BigDecimal("1")
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_equal(nil, BigDecimal("NaN") <=> n1)
    assert_equal(false, BigDecimal("NaN") > n1)
    assert_equal(nil, BigDecimal("NaN") <=> BigDecimal("NaN"))
    assert_equal(false, BigDecimal("NaN") == BigDecimal("NaN"))
  end

  def test_cmp_failing_coercion
    n1 = BigDecimal("1")
    assert_equal(nil, n1 <=> nil)
    assert_raise(ArgumentError){n1 > nil}
  end

  def test_cmp_coerce
    n1 = BigDecimal("1")
    n2 = BigDecimal("2")
    o1 = Object.new; def o1.coerce(x); [x, BigDecimal("1")]; end
    o2 = Object.new; def o2.coerce(x); [x, BigDecimal("2")]; end
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

    bug10109 = '[ruby-core:64190]'
    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    assert_operator(BigDecimal(0), :<, Float::INFINITY, bug10109)
    assert_operator(Float::INFINITY, :>, BigDecimal(0), bug10109)
  end

  def test_cmp_bignum
    assert_operator(BigDecimal((2**100).to_s), :==, 2**100)
  end

  def test_cmp_data
    d = Time.now; def d.coerce(x); [x, x]; end
    assert_operator(BigDecimal((2**100).to_s), :==, d)
  end

  def test_precs
    a = BigDecimal("1").precs
    assert_instance_of(Array, a)
    assert_equal(2, a.size)
    assert_kind_of(Integer, a[0])
    assert_kind_of(Integer, a[1])
  end

  def test_hash
    a = []
    b = BigDecimal("1")
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

    x = BigDecimal("0")
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

    x = BigDecimal("0")
    assert_kind_of(Integer, x.to_i)
    assert_equal(0, x.to_i)
    assert_raise(FloatDomainError){( 1 / x).to_i}
    assert_raise(FloatDomainError){(-1 / x).to_i}
    assert_raise(FloatDomainError) {( 0 / x).to_i}
    x = BigDecimal("1")
    assert_equal(1, x.to_i)
    x = BigDecimal((2**100).to_s)
    assert_equal(2**100, x.to_i)
  end

  def test_to_f
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)

    x = BigDecimal("0")
    assert_instance_of(Float, x.to_f)
    assert_equal(0.0, x.to_f)
    assert_equal( 1.0 / 0.0, ( 1 / x).to_f)
    assert_equal(-1.0 / 0.0, (-1 / x).to_f)
    assert_nan(( 0 / x).to_f)
    x = BigDecimal("1")
    assert_equal(1.0, x.to_f)
    x = BigDecimal((2**100).to_s)
    assert_equal((2**100).to_f, x.to_f)
    x = BigDecimal("1" + "0" * 10000)
    assert_equal(0, BigDecimal("-0").to_f)

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, true)
    assert_raise(FloatDomainError) { x.to_f }
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    assert_kind_of(Float,   x .to_f)
    assert_kind_of(Float, (-x).to_f)

    bug6944 = '[ruby-core:47342]'

    BigDecimal.mode(BigDecimal::EXCEPTION_UNDERFLOW, true)
    x = "1e#{Float::MIN_10_EXP - 2*Float::DIG}"
    assert_raise(FloatDomainError, x) {BigDecimal(x).to_f}
    x = "-#{x}"
    assert_raise(FloatDomainError, x) {BigDecimal(x).to_f}
    x = "1e#{Float::MIN_10_EXP - Float::DIG}"
    assert_nothing_raised(FloatDomainError, x) {
      assert_in_delta(0.0, BigDecimal(x).to_f, 10**Float::MIN_10_EXP, bug6944)
    }
    x = "-#{x}"
    assert_nothing_raised(FloatDomainError, x) {
      assert_in_delta(0.0, BigDecimal(x).to_f, 10**Float::MIN_10_EXP, bug6944)
    }

    BigDecimal.mode(BigDecimal::EXCEPTION_UNDERFLOW, false)
    x = "1e#{Float::MIN_10_EXP - 2*Float::DIG}"
    assert_equal( 0.0, BigDecimal(x).to_f, x)
    x = "-#{x}"
    assert_equal(-0.0, BigDecimal(x).to_f, x)
    x = "1e#{Float::MIN_10_EXP - Float::DIG}"
    assert_nothing_raised(FloatDomainError, x) {
      assert_in_delta(0.0, BigDecimal(x).to_f, 10**Float::MIN_10_EXP, bug6944)
    }
    x = "-#{x}"
    assert_nothing_raised(FloatDomainError, x) {
      assert_in_delta(0.0, BigDecimal(x).to_f, 10**Float::MIN_10_EXP, bug6944)
    }

    assert_equal( 0.0, BigDecimal(  '9e-325').to_f)
    assert_equal( 0.0, BigDecimal( '10e-325').to_f)
    assert_equal(-0.0, BigDecimal( '-9e-325').to_f)
    assert_equal(-0.0, BigDecimal('-10e-325').to_f)
  end

  def test_to_r
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)

    x = BigDecimal("0")
    assert_kind_of(Rational, x.to_r)
    assert_equal(0, x.to_r)
    assert_raise(FloatDomainError) {( 1 / x).to_r}
    assert_raise(FloatDomainError) {(-1 / x).to_r}
    assert_raise(FloatDomainError) {( 0 / x).to_r}

    assert_equal(1, BigDecimal("1").to_r)
    assert_equal(Rational(3, 2), BigDecimal("1.5").to_r)
    assert_equal((2**100).to_r, BigDecimal((2**100).to_s).to_r)
  end

  def test_coerce
    a, b = BigDecimal("1").coerce(1.0)
    assert_instance_of(BigDecimal, a)
    assert_instance_of(BigDecimal, b)
    assert_equal(2, 1 + BigDecimal("1"), '[ruby-core:25697]')

    a, b = BigDecimal("1").coerce(1.quo(10))
    assert_equal(BigDecimal("0.1"), a, '[ruby-core:34318]')

    a, b = BigDecimal("0.11111").coerce(1.quo(3))
    assert_equal(BigDecimal("0." + "3"*a.precs[0]), a)

    assert_nothing_raised(TypeError, '#7176') do
      BigDecimal('1') + Rational(1)
    end
  end

  def test_uplus
    x = BigDecimal("1")
    assert_equal(x, x.send(:+@))
  end

  def test_neg
    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)

    assert_equal(BigDecimal("-1"), BigDecimal("1").send(:-@))
    assert_equal(BigDecimal("-0"), BigDecimal("0").send(:-@))
    assert_equal(BigDecimal("0"), BigDecimal("-0").send(:-@))
    assert_equal(BigDecimal("-Infinity"), BigDecimal("Infinity").send(:-@))
    assert_equal(BigDecimal("Infinity"), BigDecimal("-Infinity").send(:-@))
    assert_equal(true, BigDecimal("NaN").send(:-@).nan?)
  end

  def test_add
    x = BigDecimal("1")
    assert_equal(BigDecimal("2"), x + x)
    assert_equal(1, BigDecimal("0") + 1)
    assert_equal(1, x + 0)

    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal("0") + 0).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal("-0") + 0).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (BigDecimal("-0") + BigDecimal("-0")).sign)

    x = BigDecimal((2**100).to_s)
    assert_equal(BigDecimal((2**100+1).to_s), x + 1)

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    inf    = BigDecimal("Infinity")
    neginf = BigDecimal("-Infinity")

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
    assert_raise_with_message(FloatDomainError, "Computation results to 'Infinity'") { inf + inf }
    assert_raise_with_message(FloatDomainError, "Computation results to '-Infinity'") { neginf + neginf }
  end

  def test_sub
    x = BigDecimal("1")
    assert_equal(BigDecimal("0"), x - x)
    assert_equal(-1, BigDecimal("0") - 1)
    assert_equal(1, x - 0)

    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal("0") - 0).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (BigDecimal("-0") - 0).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal("-0") - BigDecimal("-0")).sign)

    x = BigDecimal((2**100).to_s)
    assert_equal(BigDecimal((2**100-1).to_s), x - 1)

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    inf    = BigDecimal("Infinity")
    neginf = BigDecimal("-Infinity")

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
    assert_raise_with_message(FloatDomainError, "Computation results to 'Infinity'") { inf - neginf }
    assert_raise_with_message(FloatDomainError, "Computation results to '-Infinity'") { neginf - inf }
  end

  def test_sub_with_float
    assert_kind_of(BigDecimal, BigDecimal("3") - 1.0)
  end

  def test_sub_with_rational
    assert_kind_of(BigDecimal, BigDecimal("3") - 1.quo(3))
  end

  def test_mult
    x = BigDecimal((2**100).to_s)
    assert_equal(BigDecimal((2**100 * 3).to_s), (x * 3).to_i)
    assert_equal(x, (x * 1).to_i)
    assert_equal(x, (BigDecimal("1") * x).to_i)
    assert_equal(BigDecimal((2**200).to_s), (x * x).to_i)

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    inf    = BigDecimal("Infinity")
    neginf = BigDecimal("-Infinity")

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
    assert_raise_with_message(FloatDomainError, "Computation results to 'Infinity'") { inf * inf }
    assert_raise_with_message(FloatDomainError, "Computation results to '-Infinity'") { neginf * inf }
  end

  def test_mult_with_float
    assert_kind_of(BigDecimal, BigDecimal("3") * 1.5)
  end

  def test_mult_with_rational
    assert_kind_of(BigDecimal, BigDecimal("3") * 1.quo(3))
  end

  def test_mult_with_nil
    assert_raise(TypeError) {
      BigDecimal('1.1') * nil
    }
  end

  def test_div
    x = BigDecimal((2**100).to_s)
    assert_equal(BigDecimal((2**100 / 3).to_s), (x / 3).to_i)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (BigDecimal("0") / 1).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (BigDecimal("-0") / 1).sign)
    assert_equal(2, BigDecimal("2") / 1)
    assert_equal(-2, BigDecimal("2") / -1)

    assert_equal(BigDecimal('1486.868686869'), BigDecimal('1472.0') / BigDecimal('0.99'), '[ruby-core:59365] [#9316]')

    assert_equal(4.124045235, BigDecimal('0.9932') / (700 * BigDecimal('0.344045') / BigDecimal('1000.0')), '[#9305]')

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    assert_positive_zero(BigDecimal("1.0")  / BigDecimal("Infinity"))
    assert_negative_zero(BigDecimal("-1.0") / BigDecimal("Infinity"))
    assert_negative_zero(BigDecimal("1.0")  / BigDecimal("-Infinity"))
    assert_positive_zero(BigDecimal("-1.0") / BigDecimal("-Infinity"))

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, true)
    BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)
    assert_raise_with_message(FloatDomainError, "Computation results to 'Infinity'") { BigDecimal("1") / 0 }
    assert_raise_with_message(FloatDomainError, "Computation results to '-Infinity'") { BigDecimal("-1") / 0 }
  end

  def test_div_with_float
    assert_kind_of(BigDecimal, BigDecimal("3") / 1.5)
  end

  def test_div_with_rational
    assert_kind_of(BigDecimal, BigDecimal("3") / 1.quo(3))
  end

  def test_mod
    x = BigDecimal((2**100).to_s)
    assert_equal(1, x % 3)
    assert_equal(2, (-x) % 3)
    assert_equal(-2, x % -3)
    assert_equal(-1, (-x) % -3)
  end

  def test_mod_with_float
    assert_kind_of(BigDecimal, BigDecimal("3") % 1.5)
  end

  def test_mod_with_rational
    assert_kind_of(BigDecimal, BigDecimal("3") % 1.quo(3))
  end

  def test_remainder
    x = BigDecimal((2**100).to_s)
    assert_equal(1, x.remainder(3))
    assert_equal(-1, (-x).remainder(3))
    assert_equal(1, x.remainder(-3))
    assert_equal(-1, (-x).remainder(-3))
  end

  def test_remainder_with_float
    assert_kind_of(BigDecimal, BigDecimal("3").remainder(1.5))
  end

  def test_remainder_with_rational
    assert_kind_of(BigDecimal, BigDecimal("3").remainder(1.quo(3)))
  end

  def test_divmod
    x = BigDecimal((2**100).to_s)
    assert_equal([(x / 3).floor, 1], x.divmod(3))
    assert_equal([(-x / 3).floor, 2], (-x).divmod(3))

    assert_equal([0, 0], BigDecimal("0").divmod(2))

    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_raise(ZeroDivisionError){BigDecimal("0").divmod(0)}
  end

  def test_add_bigdecimal
    x = BigDecimal((2**100).to_s)
    assert_equal(3000000000000000000000000000000, x.add(x, 1))
    assert_equal(2500000000000000000000000000000, x.add(x, 2))
    assert_equal(2540000000000000000000000000000, x.add(x, 3))
  end

  def test_sub_bigdecimal
    x = BigDecimal((2**100).to_s)
    assert_equal(1000000000000000000000000000000, x.sub(1, 1))
    assert_equal(1300000000000000000000000000000, x.sub(1, 2))
    assert_equal(1270000000000000000000000000000, x.sub(1, 3))
  end

  def test_mult_bigdecimal
    x = BigDecimal((2**100).to_s)
    assert_equal(4000000000000000000000000000000, x.mult(3, 1))
    assert_equal(3800000000000000000000000000000, x.mult(3, 2))
    assert_equal(3800000000000000000000000000000, x.mult(3, 3))
  end

  def test_div_bigdecimal
    x = BigDecimal((2**100).to_s)
    assert_equal(422550200076076467165567735125, x.div(3))
    assert_equal(400000000000000000000000000000, x.div(3, 1))
    assert_equal(420000000000000000000000000000, x.div(3, 2))
    assert_equal(423000000000000000000000000000, x.div(3, 3))
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      assert_equal(0, BigDecimal("0").div(BigDecimal("Infinity")))
    end
  end

  def test_abs_bigdecimal
    x = BigDecimal((2**100).to_s)
    assert_equal(1267650600228229401496703205376, x.abs)
    x = BigDecimal("-" + (2**100).to_s)
    assert_equal(1267650600228229401496703205376, x.abs)
    x = BigDecimal("0")
    assert_equal(0, x.abs)
    x = BigDecimal("-0")
    assert_equal(0, x.abs)

    BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
    x = BigDecimal("Infinity")
    assert_equal(BigDecimal("Infinity"), x.abs)
    x = BigDecimal("-Infinity")
    assert_equal(BigDecimal("Infinity"), x.abs)

    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    x = BigDecimal("NaN")
    assert_nan(x.abs)
  end

  def test_sqrt_bigdecimal
    x = BigDecimal("0.09")
    assert_in_delta(0.3, x.sqrt(1), 0.001)
    x = BigDecimal((2**100).to_s)
    y = BigDecimal("1125899906842624")
    e = y.exponent
    assert_equal(true, (x.sqrt(100) - y).abs < BigDecimal("1E#{e-100}"))
    assert_equal(true, (x.sqrt(200) - y).abs < BigDecimal("1E#{e-200}"))
    assert_equal(true, (x.sqrt(300) - y).abs < BigDecimal("1E#{e-300}"))
    x = BigDecimal("-" + (2**100).to_s)
    assert_raise_with_message(FloatDomainError, "sqrt of negative value") { x.sqrt(1) }
    x = BigDecimal((2**200).to_s)
    assert_equal(2**100, x.sqrt(1))

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_raise_with_message(FloatDomainError, "sqrt of 'NaN'(Not a Number)") { BigDecimal("NaN").sqrt(1) }
    assert_raise_with_message(FloatDomainError, "sqrt of negative value") { BigDecimal("-Infinity").sqrt(1) }

    assert_equal(0, BigDecimal("0").sqrt(1))
    assert_equal(0, BigDecimal("-0").sqrt(1))
    assert_equal(1, BigDecimal("1").sqrt(1))
    assert_positive_infinite(BigDecimal("Infinity").sqrt(1))
  end

  def test_sqrt_5266
    x = BigDecimal('2' + '0'*100)
    assert_equal('0.14142135623730950488016887242096980785696718753769480731',
                 x.sqrt(56).to_s(56).split(' ')[0])
    assert_equal('0.1414213562373095048801688724209698078569671875376948073',
                 x.sqrt(55).to_s(55).split(' ')[0])

    x = BigDecimal('2' + '0'*200)
    assert_equal('0.14142135623730950488016887242096980785696718753769480731766797379907324784621070388503875343276415727350138462',
                 x.sqrt(110).to_s(110).split(' ')[0])
    assert_equal('0.1414213562373095048801688724209698078569671875376948073176679737990732478462107038850387534327641572735013846',
                 x.sqrt(109).to_s(109).split(' ')[0])
  end

  def test_fix
    x = BigDecimal("1.1")
    assert_equal(1, x.fix)
    assert_kind_of(BigDecimal, x.fix)
  end

  def test_frac
    x = BigDecimal("1.1")
    assert_equal(0.1, x.frac)
    assert_equal(0.1, BigDecimal("0.1").frac)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_nan(BigDecimal("NaN").frac)
  end

  def test_round
    assert_equal(3, BigDecimal("3.14159").round)
    assert_equal(9, BigDecimal("8.7").round)
    assert_equal(3.142, BigDecimal("3.14159").round(3))
    assert_equal(13300.0, BigDecimal("13345.234").round(-2))

    x = BigDecimal("111.111")
    assert_equal(111    , x.round)
    assert_equal(111.1  , x.round(1))
    assert_equal(111.11 , x.round(2))
    assert_equal(111.111, x.round(3))
    assert_equal(111.111, x.round(4))
    assert_equal(110    , x.round(-1))
    assert_equal(100    , x.round(-2))
    assert_equal(  0    , x.round(-3))
    assert_equal(  0    , x.round(-4))

    x = BigDecimal("2.5")
    assert_equal(3, x.round(0, BigDecimal::ROUND_UP))
    assert_equal(2, x.round(0, BigDecimal::ROUND_DOWN))
    assert_equal(3, x.round(0, BigDecimal::ROUND_HALF_UP))
    assert_equal(2, x.round(0, BigDecimal::ROUND_HALF_DOWN))
    assert_equal(2, x.round(0, BigDecimal::ROUND_HALF_EVEN))
    assert_equal(3, x.round(0, BigDecimal::ROUND_CEILING))
    assert_equal(2, x.round(0, BigDecimal::ROUND_FLOOR))
    assert_raise(ArgumentError) { x.round(0, 256) }

    x = BigDecimal("-2.5")
    assert_equal(-3, x.round(0, BigDecimal::ROUND_UP))
    assert_equal(-2, x.round(0, BigDecimal::ROUND_DOWN))
    assert_equal(-3, x.round(0, BigDecimal::ROUND_HALF_UP))
    assert_equal(-2, x.round(0, BigDecimal::ROUND_HALF_DOWN))
    assert_equal(-2, x.round(0, BigDecimal::ROUND_HALF_EVEN))
    assert_equal(-2, x.round(0, BigDecimal::ROUND_CEILING))
    assert_equal(-3, x.round(0, BigDecimal::ROUND_FLOOR))

    ROUNDING_MODE_MAP.each do |const, sym|
      assert_equal(x.round(0, const), x.round(0, sym))
    end

    bug3803 = '[ruby-core:32136]'
    15.times do |n|
      x = BigDecimal("5#{'0'*n}1")
      assert_equal(10**(n+2), x.round(-(n+2), BigDecimal::ROUND_HALF_DOWN), bug3803)
      assert_equal(10**(n+2), x.round(-(n+2), BigDecimal::ROUND_HALF_EVEN), bug3803)
      x = BigDecimal("0.5#{'0'*n}1")
      assert_equal(1, x.round(0, BigDecimal::ROUND_HALF_DOWN), bug3803)
      assert_equal(1, x.round(0, BigDecimal::ROUND_HALF_EVEN), bug3803)
      x = BigDecimal("-0.5#{'0'*n}1")
      assert_equal(-1, x.round(0, BigDecimal::ROUND_HALF_DOWN), bug3803)
      assert_equal(-1, x.round(0, BigDecimal::ROUND_HALF_EVEN), bug3803)
    end
  end

  def test_round_half_even
    assert_equal(BigDecimal('12.0'), BigDecimal('12.5').round(half: :even))
    assert_equal(BigDecimal('14.0'), BigDecimal('13.5').round(half: :even))

    assert_equal(BigDecimal('2.2'), BigDecimal('2.15').round(1, half: :even))
    assert_equal(BigDecimal('2.2'), BigDecimal('2.25').round(1, half: :even))
    assert_equal(BigDecimal('2.4'), BigDecimal('2.35').round(1, half: :even))

    assert_equal(BigDecimal('-2.2'), BigDecimal('-2.15').round(1, half: :even))
    assert_equal(BigDecimal('-2.2'), BigDecimal('-2.25').round(1, half: :even))
    assert_equal(BigDecimal('-2.4'), BigDecimal('-2.35').round(1, half: :even))

    assert_equal(BigDecimal('7.1364'), BigDecimal('7.13645').round(4, half: :even))
    assert_equal(BigDecimal('7.1365'), BigDecimal('7.1364501').round(4, half: :even))
    assert_equal(BigDecimal('7.1364'), BigDecimal('7.1364499').round(4, half: :even))

    assert_equal(BigDecimal('-7.1364'), BigDecimal('-7.13645').round(4, half: :even))
    assert_equal(BigDecimal('-7.1365'), BigDecimal('-7.1364501').round(4, half: :even))
    assert_equal(BigDecimal('-7.1364'), BigDecimal('-7.1364499').round(4, half: :even))
  end

  def test_round_half_up
    assert_equal(BigDecimal('13.0'), BigDecimal('12.5').round(half: :up))
    assert_equal(BigDecimal('14.0'), BigDecimal('13.5').round(half: :up))

    assert_equal(BigDecimal('2.2'), BigDecimal('2.15').round(1, half: :up))
    assert_equal(BigDecimal('2.3'), BigDecimal('2.25').round(1, half: :up))
    assert_equal(BigDecimal('2.4'), BigDecimal('2.35').round(1, half: :up))

    assert_equal(BigDecimal('-2.2'), BigDecimal('-2.15').round(1, half: :up))
    assert_equal(BigDecimal('-2.3'), BigDecimal('-2.25').round(1, half: :up))
    assert_equal(BigDecimal('-2.4'), BigDecimal('-2.35').round(1, half: :up))

    assert_equal(BigDecimal('7.1365'), BigDecimal('7.13645').round(4, half: :up))
    assert_equal(BigDecimal('7.1365'), BigDecimal('7.1364501').round(4, half: :up))
    assert_equal(BigDecimal('7.1364'), BigDecimal('7.1364499').round(4, half: :up))

    assert_equal(BigDecimal('-7.1365'), BigDecimal('-7.13645').round(4, half: :up))
    assert_equal(BigDecimal('-7.1365'), BigDecimal('-7.1364501').round(4, half: :up))
    assert_equal(BigDecimal('-7.1364'), BigDecimal('-7.1364499').round(4, half: :up))
  end

  def test_round_half_down
    assert_equal(BigDecimal('12.0'), BigDecimal('12.5').round(half: :down))
    assert_equal(BigDecimal('13.0'), BigDecimal('13.5').round(half: :down))

    assert_equal(BigDecimal('2.1'), BigDecimal('2.15').round(1, half: :down))
    assert_equal(BigDecimal('2.2'), BigDecimal('2.25').round(1, half: :down))
    assert_equal(BigDecimal('2.3'), BigDecimal('2.35').round(1, half: :down))

    assert_equal(BigDecimal('-2.1'), BigDecimal('-2.15').round(1, half: :down))
    assert_equal(BigDecimal('-2.2'), BigDecimal('-2.25').round(1, half: :down))
    assert_equal(BigDecimal('-2.3'), BigDecimal('-2.35').round(1, half: :down))

    assert_equal(BigDecimal('7.1364'), BigDecimal('7.13645').round(4, half: :down))
    assert_equal(BigDecimal('7.1365'), BigDecimal('7.1364501').round(4, half: :down))
    assert_equal(BigDecimal('7.1364'), BigDecimal('7.1364499').round(4, half: :down))

    assert_equal(BigDecimal('-7.1364'), BigDecimal('-7.13645').round(4, half: :down))
    assert_equal(BigDecimal('-7.1365'), BigDecimal('-7.1364501').round(4, half: :down))
    assert_equal(BigDecimal('-7.1364'), BigDecimal('-7.1364499').round(4, half: :down))
  end

  def test_round_half_nil
    x = BigDecimal("2.5")

    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_UP)
      assert_equal(3, x.round(0, half: nil))
    end

    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_DOWN)
      assert_equal(2, x.round(0, half: nil))
    end

    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_UP)
      assert_equal(3, x.round(0, half: nil))
    end

    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_DOWN)
      assert_equal(2, x.round(0, half: nil))
    end

    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_HALF_EVEN)
      assert_equal(2, x.round(0, half: nil))
    end

    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_CEILING)
      assert_equal(3, x.round(0, half: nil))
    end

    BigDecimal.save_rounding_mode do
      BigDecimal.mode(BigDecimal::ROUND_MODE, BigDecimal::ROUND_FLOOR)
      assert_equal(2, x.round(0, half: nil))
    end
  end

  def test_round_half_invalid_option
    assert_raise_with_message(ArgumentError, "invalid rounding mode: invalid") { BigDecimal('12.5').round(half: :invalid) }
    assert_raise_with_message(ArgumentError, "invalid rounding mode: invalid") { BigDecimal('2.15').round(1, half: :invalid) }
  end

  def test_truncate
    assert_equal(3, BigDecimal("3.14159").truncate)
    assert_equal(8, BigDecimal("8.7").truncate)
    assert_equal(3.141, BigDecimal("3.14159").truncate(3))
    assert_equal(13300.0, BigDecimal("13345.234").truncate(-2))

    assert_equal(-3, BigDecimal("-3.14159").truncate)
    assert_equal(-8, BigDecimal("-8.7").truncate)
    assert_equal(-3.141, BigDecimal("-3.14159").truncate(3))
    assert_equal(-13300.0, BigDecimal("-13345.234").truncate(-2))
  end

  def test_floor
    assert_equal(3, BigDecimal("3.14159").floor)
    assert_equal(-10, BigDecimal("-9.1").floor)
    assert_equal(3.141, BigDecimal("3.14159").floor(3))
    assert_equal(13300.0, BigDecimal("13345.234").floor(-2))
  end

  def test_ceil
    assert_equal(4, BigDecimal("3.14159").ceil)
    assert_equal(-9, BigDecimal("-9.1").ceil)
    assert_equal(3.142, BigDecimal("3.14159").ceil(3))
    assert_equal(13400.0, BigDecimal("13345.234").ceil(-2))
  end

  def test_to_s
    assert_equal('-123.45678 90123 45678 9', BigDecimal('-123.45678901234567890').to_s('5F'))
    assert_equal('+123.45678901 23456789', BigDecimal('123.45678901234567890').to_s('+8F'))
    assert_equal(' 123.4567890123456789', BigDecimal('123.45678901234567890').to_s(' F'))
    assert_equal('0.1234567890123456789e3', BigDecimal('123.45678901234567890').to_s)
    assert_equal('0.12345 67890 12345 6789e3', BigDecimal('123.45678901234567890').to_s(5))
  end

  def test_split
    x = BigDecimal('-123.45678901234567890')
    assert_equal([-1, "1234567890123456789", 10, 3], x.split)
    assert_equal([1, "0", 10, 0], BigDecimal("0").split)
    assert_equal([-1, "0", 10, 0], BigDecimal("-0").split)

    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    assert_equal([0, "NaN", 10, 0], BigDecimal("NaN").split)
    assert_equal([1, "Infinity", 10, 0], BigDecimal("Infinity").split)
    assert_equal([-1, "Infinity", 10, 0], BigDecimal("-Infinity").split)
  end

  def test_exponent
    x = BigDecimal('-123.45678901234567890')
    assert_equal(3, x.exponent)
  end

  def test_inspect
    assert_equal("0.123456789012e0", BigDecimal("0.123456789012").inspect)
    assert_equal("0.123456789012e4", BigDecimal("1234.56789012").inspect)
    assert_equal("0.123456789012e-4", BigDecimal("0.0000123456789012").inspect)
  end

  def test_power
    assert_nothing_raised(TypeError, '[ruby-core:47632]') do
      1000.times { BigDecimal('1001.10')**0.75 }
    end
  end

  def test_power_with_nil
    assert_raise(TypeError) do
      BigDecimal(3) ** nil
    end
  end

  def test_power_of_nan
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_nan(BigDecimal::NAN ** 0)
      assert_nan(BigDecimal::NAN ** 1)
      assert_nan(BigDecimal::NAN ** 42)
      assert_nan(BigDecimal::NAN ** -42)
      assert_nan(BigDecimal::NAN ** 42.0)
      assert_nan(BigDecimal::NAN ** -42.0)
      assert_nan(BigDecimal::NAN ** BigDecimal(42))
      assert_nan(BigDecimal::NAN ** BigDecimal(-42))
      assert_nan(BigDecimal::NAN ** BigDecimal::INFINITY)
      BigDecimal.save_exception_mode do
        BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
        assert_nan(BigDecimal::NAN ** (-BigDecimal::INFINITY))
      end
    end
  end

  def test_power_with_Bignum
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      assert_equal(0, BigDecimal(0) ** (2**100))

      assert_positive_infinite(BigDecimal(0) ** -(2**100))
      assert_positive_infinite((-BigDecimal(0)) ** -(2**100))
      assert_negative_infinite((-BigDecimal(0)) ** -(2**100 + 1))

      assert_equal(1, BigDecimal(1) ** (2**100))

      assert_positive_infinite(BigDecimal(3) ** (2**100))
      assert_positive_zero(BigDecimal(3) ** (-2**100))

      assert_negative_infinite(BigDecimal(-3) ** (2**100))
      assert_positive_infinite(BigDecimal(-3) ** (2**100 + 1))
      assert_negative_zero(BigDecimal(-3) ** (-2**100))
      assert_positive_zero(BigDecimal(-3) ** (-2**100 - 1))

      assert_positive_zero(BigDecimal(0.5, Float::DIG) ** (2**100))
      assert_positive_infinite(BigDecimal(0.5, Float::DIG) ** (-2**100))

      assert_negative_zero(BigDecimal(-0.5, Float::DIG) ** (2**100))
      assert_positive_zero(BigDecimal(-0.5, Float::DIG) ** (2**100 - 1))
      assert_negative_infinite(BigDecimal(-0.5, Float::DIG) ** (-2**100))
      assert_positive_infinite(BigDecimal(-0.5, Float::DIG) ** (-2**100 - 1))
    end
  end

  def test_power_with_BigDecimal
    assert_nothing_raised do
      assert_in_delta(3 ** 3, BigDecimal(3) ** BigDecimal(3))
    end
  end

  def test_power_of_finite_with_zero
    x = BigDecimal(1)
    assert_equal(1, x ** 0)
    assert_equal(1, x ** 0.quo(1))
    assert_equal(1, x ** 0.0)
    assert_equal(1, x ** BigDecimal(0))

    x = BigDecimal(42)
    assert_equal(1, x ** 0)
    assert_equal(1, x ** 0.quo(1))
    assert_equal(1, x ** 0.0)
    assert_equal(1, x ** BigDecimal(0))

    x = BigDecimal(-42)
    assert_equal(1, x ** 0)
    assert_equal(1, x ** 0.quo(1))
    assert_equal(1, x ** 0.0)
    assert_equal(1, x ** BigDecimal(0))
  end

  def test_power_of_three
    x = BigDecimal(3)
    assert_equal(81, x ** 4)
    assert_equal(1.quo(81), x ** -4)
    assert_in_delta(1.0/81, x ** -4)
  end

  def test_power_of_zero
    zero = BigDecimal(0)
    assert_equal(0, zero ** 4)
    assert_equal(0, zero ** 4.quo(1))
    assert_equal(0, zero ** 4.0)
    assert_equal(0, zero ** BigDecimal(4))
    assert_equal(1, zero ** 0)
    assert_equal(1, zero ** 0.quo(1))
    assert_equal(1, zero ** 0.0)
    assert_equal(1, zero ** BigDecimal(0))
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
      assert_positive_infinite(zero ** -1)
      assert_positive_infinite(zero ** -1.quo(1))
      assert_positive_infinite(zero ** -1.0)
      assert_positive_infinite(zero ** BigDecimal(-1))

      m_zero = BigDecimal("-0")
      assert_negative_infinite(m_zero ** -1)
      assert_negative_infinite(m_zero ** -1.quo(1))
      assert_negative_infinite(m_zero ** -1.0)
      assert_negative_infinite(m_zero ** BigDecimal(-1))
      assert_positive_infinite(m_zero ** -2)
      assert_positive_infinite(m_zero ** -2.quo(1))
      assert_positive_infinite(m_zero ** -2.0)
      assert_positive_infinite(m_zero ** BigDecimal(-2))
    end
  end

  def test_power_of_positive_infinity
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
      assert_positive_infinite(BigDecimal::INFINITY ** 3)
      assert_positive_infinite(BigDecimal::INFINITY ** 3.quo(1))
      assert_positive_infinite(BigDecimal::INFINITY ** 3.0)
      assert_positive_infinite(BigDecimal::INFINITY ** BigDecimal(3))
      assert_positive_infinite(BigDecimal::INFINITY ** 2)
      assert_positive_infinite(BigDecimal::INFINITY ** 2.quo(1))
      assert_positive_infinite(BigDecimal::INFINITY ** 2.0)
      assert_positive_infinite(BigDecimal::INFINITY ** BigDecimal(2))
      assert_positive_infinite(BigDecimal::INFINITY ** 1)
      assert_positive_infinite(BigDecimal::INFINITY ** 1.quo(1))
      assert_positive_infinite(BigDecimal::INFINITY ** 1.0)
      assert_positive_infinite(BigDecimal::INFINITY ** BigDecimal(1))
      assert_equal(1, BigDecimal::INFINITY ** 0)
      assert_equal(1, BigDecimal::INFINITY ** 0.quo(1))
      assert_equal(1, BigDecimal::INFINITY ** 0.0)
      assert_equal(1, BigDecimal::INFINITY ** BigDecimal(0))
      assert_positive_zero(BigDecimal::INFINITY ** -1)
      assert_positive_zero(BigDecimal::INFINITY ** -1.quo(1))
      assert_positive_zero(BigDecimal::INFINITY ** -1.0)
      assert_positive_zero(BigDecimal::INFINITY ** BigDecimal(-1))
      assert_positive_zero(BigDecimal::INFINITY ** -2)
      assert_positive_zero(BigDecimal::INFINITY ** -2.0)
      assert_positive_zero(BigDecimal::INFINITY ** BigDecimal(-2))
    end
  end

  def test_power_of_negative_infinity
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
      assert_negative_infinite((-BigDecimal::INFINITY) ** 3)
      assert_negative_infinite((-BigDecimal::INFINITY) ** 3.quo(1))
      assert_negative_infinite((-BigDecimal::INFINITY) ** 3.0)
      assert_negative_infinite((-BigDecimal::INFINITY) ** BigDecimal(3))
      assert_positive_infinite((-BigDecimal::INFINITY) ** 2)
      assert_positive_infinite((-BigDecimal::INFINITY) ** 2.quo(1))
      assert_positive_infinite((-BigDecimal::INFINITY) ** 2.0)
      assert_positive_infinite((-BigDecimal::INFINITY) ** BigDecimal(2))
      assert_negative_infinite((-BigDecimal::INFINITY) ** 1)
      assert_negative_infinite((-BigDecimal::INFINITY) ** 1.quo(1))
      assert_negative_infinite((-BigDecimal::INFINITY) ** 1.0)
      assert_negative_infinite((-BigDecimal::INFINITY) ** BigDecimal(1))
      assert_equal(1, (-BigDecimal::INFINITY) ** 0)
      assert_equal(1, (-BigDecimal::INFINITY) ** 0.quo(1))
      assert_equal(1, (-BigDecimal::INFINITY) ** 0.0)
      assert_equal(1, (-BigDecimal::INFINITY) ** BigDecimal(0))
      assert_negative_zero((-BigDecimal::INFINITY) ** -1)
      assert_negative_zero((-BigDecimal::INFINITY) ** -1.quo(1))
      assert_negative_zero((-BigDecimal::INFINITY) ** -1.0)
      assert_negative_zero((-BigDecimal::INFINITY) ** BigDecimal(-1))
      assert_positive_zero((-BigDecimal::INFINITY) ** -2)
      assert_positive_zero((-BigDecimal::INFINITY) ** -2.quo(1))
      assert_positive_zero((-BigDecimal::INFINITY) ** -2.0)
      assert_positive_zero((-BigDecimal::INFINITY) ** BigDecimal(-2))
    end
  end

  def test_power_without_prec
    pi  = BigDecimal("3.14159265358979323846264338327950288419716939937511")
    e   = BigDecimal("2.71828182845904523536028747135266249775724709369996")
    pow = BigDecimal("22.4591577183610454734271522045437350275893151339967843873233068")
    assert_equal(pow, pi.power(e))
  end

  def test_power_with_prec
    pi  = BigDecimal("3.14159265358979323846264338327950288419716939937511")
    e   = BigDecimal("2.71828182845904523536028747135266249775724709369996")
    pow = BigDecimal("22.459157718361045473")
    assert_equal(pow, pi.power(e, 20))

    b = BigDecimal('1.034482758620689655172413793103448275862068965517241379310344827586206896551724')
    assert_equal(BigDecimal('0.114523E1'), b.power(4, 5), '[Bug #8818] [ruby-core:56802]')
  end

  def test_limit
    BigDecimal.limit(1)
    x = BigDecimal("3")
    assert_equal(90, x ** 4) # OK? must it be 80?
    # 3 * 3 * 3 * 3 = 10 * 3 * 3 = 30 * 3 = 90 ???
    assert_raise(ArgumentError) { BigDecimal.limit(-1) }

    bug7458 = '[ruby-core:50269] [#7458]'
    one = BigDecimal('1')
    epsilon = BigDecimal('0.7E-18')
    BigDecimal.save_limit do
      BigDecimal.limit(0)
      assert_equal(BigDecimal("1.0000000000000000007"), one + epsilon, "limit(0) #{bug7458}")

      1.upto(18) do |lim|
        BigDecimal.limit(lim)
        assert_equal(BigDecimal("1.0"), one + epsilon, "limit(#{lim}) #{bug7458}")
      end

      BigDecimal.limit(19)
      assert_equal(BigDecimal("1.000000000000000001"), one + epsilon, "limit(19) #{bug7458}")

      BigDecimal.limit(20)
      assert_equal(BigDecimal("1.0000000000000000007"), one + epsilon, "limit(20) #{bug7458}")
    end
  end

  def test_sign
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)

    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, BigDecimal("0").sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, BigDecimal("-0").sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_FINITE, BigDecimal("1").sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_FINITE, BigDecimal("-1").sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_INFINITE, (BigDecimal("1") / 0).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_INFINITE, (BigDecimal("-1") / 0).sign)
    assert_equal(BigDecimal::SIGN_NaN, (BigDecimal("0") / 0).sign)
  end

  def test_inf
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    inf = BigDecimal("Infinity")

    assert_equal(inf, inf + inf)
    assert_nan((inf + (-inf)))
    assert_nan((inf - inf))
    assert_equal(inf, inf - (-inf))
    assert_equal(inf, inf * inf)
    assert_nan((inf / inf))

    assert_equal(inf, inf + 1)
    assert_equal(inf, inf - 1)
    assert_equal(inf, inf * 1)
    assert_nan((inf * 0))
    assert_equal(inf, inf / 1)

    assert_equal(inf, 1 + inf)
    assert_equal(-inf, 1 - inf)
    assert_equal(inf, 1 * inf)
    assert_equal(-inf, -1 * inf)
    assert_nan((0 * inf))
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, (1 / inf).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, (-1 / inf).sign)
  end

  def test_to_special_string
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)
    BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
    nan = BigDecimal("NaN")
    assert_equal("NaN", nan.to_s)
    inf = BigDecimal("Infinity")
    assert_equal("Infinity", inf.to_s)
    assert_equal(" Infinity", inf.to_s(" "))
    assert_equal("+Infinity", inf.to_s("+"))
    assert_equal("-Infinity", (-inf).to_s)
    pzero = BigDecimal("0")
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
    assert_equal(0.1, BigDecimal("1E-1"))
    assert_equal(10, BigDecimal("1E+1"))
    assert_equal(1, BigDecimal("+1"))
    BigDecimal.mode(BigDecimal::EXCEPTION_OVERFLOW, false)

    assert_equal(BigDecimal::SIGN_POSITIVE_INFINITE, BigDecimal("1E1" + "0" * 10000).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_INFINITE, BigDecimal("-1E1" + "0" * 10000).sign)
    assert_equal(BigDecimal::SIGN_POSITIVE_ZERO, BigDecimal("1E-1" + "0" * 10000).sign)
    assert_equal(BigDecimal::SIGN_NEGATIVE_ZERO, BigDecimal("-1E-1" + "0" * 10000).sign)
  end

  def test_split_under_gc_stress
    bug3258 = '[ruby-dev:41213]'
    expect = 10.upto(20).map{|i|[1, "1", 10, i+1].inspect}
    assert_in_out_err(%w[-rbigdecimal --disable-gems], <<-EOS, expect, [], bug3258)
    GC.stress = true
    10.upto(20) do |i|
      p BigDecimal("1"+"0"*i).split
    end
    EOS
  end

  def test_coerce_under_gc_stress
    assert_in_out_err(%w[-rbigdecimal --disable-gems], <<-EOS, [], [])
      expect = ":too_long_to_embed_as_string can't be coerced into BigDecimal"
      b = BigDecimal("1")
      GC.stress = true
      10.times do
        begin
          b.coerce(:too_long_to_embed_as_string)
        rescue => e
          raise unless e.is_a?(TypeError)
          raise "'\#{expect}' is expected, but '\#{e.message}'" unless e.message == expect
        end
      end
    EOS
  end

  def test_INFINITY
    assert_positive_infinite(BigDecimal::INFINITY)
  end

  def test_NAN
    assert_nan(BigDecimal::NAN)
  end

  def test_exp_with_zero_precision
    assert_raise(ArgumentError) do
      BigMath.exp(1, 0)
    end
  end

  def test_exp_with_negative_precision
    assert_raise(ArgumentError) do
      BigMath.exp(1, -42)
    end
  end

  def test_exp_with_complex
    assert_raise(ArgumentError) do
      BigMath.exp(Complex(1, 2), 20)
    end
  end

  def test_exp_with_negative
    x = BigDecimal(-1)
    y = BigMath.exp(x, 20)
    assert_equal(y, BigMath.exp(-1, 20))
    assert_equal(BigDecimal(-1), x)
  end

  def test_exp_with_negative_infinite
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      assert_equal(0, BigMath.exp(-BigDecimal::INFINITY, 20))
    end
  end

  def test_exp_with_positive_infinite
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      assert(BigMath.exp(BigDecimal::INFINITY, 20) > 0)
      assert_positive_infinite(BigMath.exp(BigDecimal::INFINITY, 20))
    end
  end

  def test_exp_with_nan
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_nan(BigMath.exp(BigDecimal::NAN, 20))
    end
  end

  def test_exp_with_1
    assert_in_epsilon(Math::E, BigMath.exp(1, 20))
  end

  def test_BigMath_exp
    prec = 20
    assert_in_epsilon(Math.exp(20), BigMath.exp(BigDecimal("20"), prec))
    assert_in_epsilon(Math.exp(40), BigMath.exp(BigDecimal("40"), prec))
    assert_in_epsilon(Math.exp(-20), BigMath.exp(BigDecimal("-20"), prec))
    assert_in_epsilon(Math.exp(-40), BigMath.exp(BigDecimal("-40"), prec))
  end

  def test_BigMath_exp_with_float
    prec = 20
    assert_in_epsilon(Math.exp(20), BigMath.exp(20.0, prec))
    assert_in_epsilon(Math.exp(40), BigMath.exp(40.0, prec))
    assert_in_epsilon(Math.exp(-20), BigMath.exp(-20.0, prec))
    assert_in_epsilon(Math.exp(-40), BigMath.exp(-40.0, prec))
  end

  def test_BigMath_exp_with_fixnum
    prec = 20
    assert_in_epsilon(Math.exp(20), BigMath.exp(20, prec))
    assert_in_epsilon(Math.exp(40), BigMath.exp(40, prec))
    assert_in_epsilon(Math.exp(-20), BigMath.exp(-20, prec))
    assert_in_epsilon(Math.exp(-40), BigMath.exp(-40, prec))
  end

  def test_BigMath_exp_with_rational
    prec = 20
    assert_in_epsilon(Math.exp(20), BigMath.exp(Rational(40,2), prec))
    assert_in_epsilon(Math.exp(40), BigMath.exp(Rational(80,2), prec))
    assert_in_epsilon(Math.exp(-20), BigMath.exp(Rational(-40,2), prec))
    assert_in_epsilon(Math.exp(-40), BigMath.exp(Rational(-80,2), prec))
  end

  def test_BigMath_exp_under_gc_stress
    assert_in_out_err(%w[-rbigdecimal --disable-gems], <<-EOS, [], [])
      expect = ":too_long_to_embed_as_string can't be coerced into BigDecimal"
      10.times do
        begin
          BigMath.exp(:too_long_to_embed_as_string, 6)
        rescue => e
          raise unless e.is_a?(ArgumentError)
          raise "'\#{expect}' is expected, but '\#{e.message}'" unless e.message == expect
        end
      end
    EOS
  end

  def test_BigMath_log_with_string
    assert_raise(ArgumentError) do
      BigMath.log("foo", 20)
    end
  end

  def test_BigMath_log_with_nil
    assert_raise(ArgumentError) do
      BigMath.log(nil, 20)
    end
  end

  def test_BigMath_log_with_non_integer_precision
    assert_raise(ArgumentError) do
      BigMath.log(1, 0.5)
    end
  end

  def test_BigMath_log_with_nil_precision
    assert_raise(ArgumentError) do
      BigMath.log(1, nil)
    end
  end

  def test_BigMath_log_with_complex
    assert_raise(Math::DomainError) do
      BigMath.log(Complex(1, 2), 20)
    end
  end

  def test_BigMath_log_with_zero_arg
    assert_raise(Math::DomainError) do
      BigMath.log(0, 20)
    end
  end

  def test_BigMath_log_with_negative_arg
    assert_raise(Math::DomainError) do
      BigMath.log(-1, 20)
    end
  end

  def test_BigMath_log_with_zero_precision
    assert_raise(ArgumentError) do
      BigMath.log(1, 0)
    end
  end

  def test_BigMath_log_with_negative_precision
    assert_raise(ArgumentError) do
      BigMath.log(1, -42)
    end
  end

  def test_BigMath_log_with_negative_infinite
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      assert_raise(Math::DomainError) do
        BigMath.log(-BigDecimal::INFINITY, 20)
      end
    end
  end

  def test_BigMath_log_with_positive_infinite
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_INFINITY, false)
      assert(BigMath.log(BigDecimal::INFINITY, 20) > 0)
      assert_positive_infinite(BigMath.log(BigDecimal::INFINITY, 20))
    end
  end

  def test_BigMath_log_with_nan
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_nan(BigMath.log(BigDecimal::NAN, 20))
    end
  end

  def test_BigMath_log_with_float_nan
    BigDecimal.save_exception_mode do
      BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      assert_nan(BigMath.log(Float::NAN, 20))
    end
  end

  def test_BigMath_log_with_1
    assert_in_delta(0.0, BigMath.log(1, 20))
    assert_in_delta(0.0, BigMath.log(1.0, 20))
    assert_in_delta(0.0, BigMath.log(BigDecimal(1), 20))
  end

  def test_BigMath_log_with_exp_1
    assert_in_delta(1.0, BigMath.log(BigMath.E(10), 10))
  end

  def test_BigMath_log_with_2
    assert_in_delta(Math.log(2), BigMath.log(2, 20))
    assert_in_delta(Math.log(2), BigMath.log(2.0, 20))
    assert_in_delta(Math.log(2), BigMath.log(BigDecimal(2), 20))
  end

  def test_BigMath_log_with_square_of_E
    assert_in_delta(2, BigMath.log(BigMath.E(20)**2, 20))
  end

  def test_BigMath_log_with_high_precision_case
    e   = BigDecimal('2.71828182845904523536028747135266249775724709369996')
    e_3 = e.mult(e, 50).mult(e, 50)
    log_3 = BigMath.log(e_3, 50)
    assert_in_delta(3, log_3, 0.0000000000_0000000000_0000000000_0000000000_0000000001)
  end

  def test_BigMath_log_with_42
    assert_in_delta(Math.log(42), BigMath.log(42, 20))
    assert_in_delta(Math.log(42), BigMath.log(42.0, 20))
    assert_in_delta(Math.log(42), BigMath.log(BigDecimal(42), 20))
  end

  def test_BigMath_log_with_101
    # this is mainly a performance test (should be very fast, not the 0.3 s)
    assert_in_delta(Math.log(101), BigMath.log(101, 20), 1E-15)
  end

  def test_BigMath_log_with_reciprocal_of_42
    assert_in_delta(Math.log(1e-42), BigMath.log(1e-42, 20))
    assert_in_delta(Math.log(1e-42), BigMath.log(BigDecimal("1e-42"), 20))
  end

  def test_BigMath_log_under_gc_stress
    assert_in_out_err(%w[-rbigdecimal --disable-gems], <<-EOS, [], [])
      expect = ":too_long_to_embed_as_string can't be coerced into BigDecimal"
      10.times do
        begin
          BigMath.log(:too_long_to_embed_as_string, 6)
        rescue => e
          raise unless e.is_a?(ArgumentError)
          raise "'\#{expect}' is expected, but '\#{e.message}'" unless e.message == expect
        end
      end
    EOS
  end

  def test_frozen_p
    x = BigDecimal(1)
    assert(x.frozen?)
    assert((x + x).frozen?)
  end

  def test_clone
    assert_warning(/^$/) do
      x = BigDecimal(0)
      assert_same(x, x.clone)
    end
  end

  def test_dup
    assert_warning(/^$/) do
      [1, -1, 2**100, -2**100].each do |i|
        x = BigDecimal(i)
        assert_same(x, x.dup)
      end
    end
  end

  def test_new_subclass
    c = Class.new(BigDecimal)
    assert_raise_with_message(NoMethodError, /undefined method `new'/) { c.new(1) }
  end

  def test_to_d
    bug6093 = '[ruby-core:42969]'
    code = "exit(BigDecimal('10.0') == 10.0.to_d)"
    assert_ruby_status(%w[-rbigdecimal -rbigdecimal/util -rmathn -], code, bug6093)
  end if RUBY_VERSION < '2.5' # mathn was removed from Ruby 2.5

  def test_bug6406
    assert_in_out_err(%w[-rbigdecimal --disable-gems], <<-EOS, [], [])
    Thread.current.keys.to_s
    EOS
  end

  def test_no_initialize_copy
    assert_equal(false, BigDecimal(1).respond_to?(:initialize_copy, true))
    assert_equal(false, BigDecimal(1).respond_to?(:initialize_dup, true))
    assert_equal(false, BigDecimal(1).respond_to?(:initialize_clone, true))
  end

  def assert_no_memory_leak(code, *rest, **opt)
    code = "8.times {20_000.times {begin #{code}; rescue NoMemoryError; end}; GC.start}"
    super(["-rbigdecimal"],
          "b = BigDecimal('10'); b.nil?; " \
          "GC.add_stress_to_class(BigDecimal); "\
          "#{code}", code, *rest, rss: true, limit: 1.1, **opt)
  end

  if EnvUtil.gc_stress_to_class?
    def test_no_memory_leak_allocate
      assert_no_memory_leak("BigDecimal.allocate")
    end

    def test_no_memory_leak_initialize
      assert_no_memory_leak("BigDecimal()")
    end

    def test_no_memory_leak_BigDecimal
      assert_no_memory_leak("BigDecimal('10')")
      assert_no_memory_leak("BigDecimal(b)")
    end

    def test_no_memory_leak_create
      assert_no_memory_leak("b + 10")
    end
  end
end
