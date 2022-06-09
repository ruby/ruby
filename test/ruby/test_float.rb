# frozen_string_literal: false
require 'test/unit'

class TestFloat < Test::Unit::TestCase
  include EnvUtil

  def test_float
    assert_equal(2, 2.6.floor)
    assert_equal(-3, (-2.6).floor)
    assert_equal(3, 2.6.ceil)
    assert_equal(-2, (-2.6).ceil)
    assert_equal(2, 2.6.truncate)
    assert_equal(-2, (-2.6).truncate)
    assert_equal(3, 2.6.round)
    assert_equal(-2, (-2.4).truncate)
    assert_in_delta(13.4 % 1, 0.4, 0.0001)
    assert_equal(36893488147419111424,
                 36893488147419107329.0.to_i)
    assert_equal(1185151044158398820374743613440,
                 1.1851510441583988e+30.to_i)
  end

  def nan_test(x,y)
    extend Test::Unit::Assertions
    assert_operator(x, :!=, y)
    assert_not_operator(x, :<, y)
    assert_not_operator(x, :>, y)
    assert_not_operator(x, :<=, y)
    assert_not_operator(x, :>=, y)
  end
  def test_nan
    nan = Float::NAN
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

  def test_cmp_int
    100.times {|i|
      int0 = 1 << i
      [int0, -int0].each {|int|
        flt = int.to_f
        bigger = int + 1
        smaller = int - 1
        assert_operator(flt, :==, int)
        assert_operator(flt, :>, smaller)
        assert_operator(flt, :>=, smaller)
        assert_operator(flt, :<, bigger)
        assert_operator(flt, :<=, bigger)
        assert_equal(0, flt <=> int)
        assert_equal(-1, flt <=> bigger)
        assert_equal(1, flt <=> smaller)
        assert_operator(int, :==, flt)
        assert_operator(bigger, :>, flt)
        assert_operator(bigger, :>=, flt)
        assert_operator(smaller, :<, flt)
        assert_operator(smaller, :<=, flt)
        assert_equal(0, int <=> flt)
        assert_equal(-1, smaller <=> flt)
        assert_equal(1, bigger <=> flt)
        [
          [int, flt + 0.5, bigger],
          [smaller, flt - 0.5, int]
        ].each {|smaller2, flt2, bigger2|
          next if flt2 == flt2.round
          assert_operator(flt2, :!=, smaller2)
          assert_operator(flt2, :!=, bigger2)
          assert_operator(flt2, :>, smaller2)
          assert_operator(flt2, :>=, smaller2)
          assert_operator(flt2, :<, bigger2)
          assert_operator(flt2, :<=, bigger2)
          assert_equal(-1, flt2 <=> bigger2)
          assert_equal(1, flt2 <=> smaller2)
          assert_operator(smaller2, :!=, flt2)
          assert_operator(bigger2, :!=, flt2)
          assert_operator(bigger2, :>, flt2)
          assert_operator(bigger2, :>=, flt2)
          assert_operator(smaller2, :<, flt2)
          assert_operator(smaller2, :<=, flt2)
          assert_equal(-1, smaller2 <=> flt2)
          assert_equal(1, bigger2 <=> flt2)
        }
      }
    }
  end

  def test_strtod
    a = Float("0")
    assert_in_delta(a, 0, Float::EPSILON)
    a = Float("0.0")
    assert_in_delta(a, 0, Float::EPSILON)
    a = Float("+0.0")
    assert_in_delta(a, 0, Float::EPSILON)
    a = Float("-0.0")
    assert_in_delta(a, 0, Float::EPSILON)
    a = Float("0.0000000000000000001")
    assert_not_equal(0.0, a)
    a = Float("+0.0000000000000000001")
    assert_not_equal(0.0, a)
    a = Float("-0.0000000000000000001")
    assert_not_equal(0.0, a)
    a = Float(".0")
    assert_in_delta(a, 0, Float::EPSILON)
    a = Float("+.0")
    assert_in_delta(a, 0, Float::EPSILON)
    a = Float("-.0")
    assert_in_delta(a, 0, Float::EPSILON)
    assert_raise(ArgumentError){Float("0.")}
    assert_raise(ArgumentError){Float("+0.")}
    assert_raise(ArgumentError){Float("-0.")}
    assert_raise(ArgumentError){Float(".")}
    assert_raise(ArgumentError){Float("+")}
    assert_raise(ArgumentError){Float("+.")}
    assert_raise(ArgumentError){Float("-")}
    assert_raise(ArgumentError){Float("-.")}
    assert_raise(ArgumentError){Float("1e")}
    assert_raise(ArgumentError){Float("1__1")}
    assert_raise(ArgumentError){Float("1.")}
    assert_raise(ArgumentError){Float("1.e+00")}
    assert_raise(ArgumentError){Float("0x1.p+0")}
    # add expected behaviour here.
    assert_equal(10, Float("1_0"))

    assert_equal([ 0.0].pack('G'), [Float(" 0x0p+0").to_f].pack('G'))
    assert_equal([-0.0].pack('G'), [Float("-0x0p+0").to_f].pack('G'))
    assert_equal(255.0,     Float("0Xff"))
    assert_equal(1024.0,    Float("0x1p10"))
    assert_equal(1024.0,    Float("0x1p+10"))
    assert_equal(0.0009765625, Float("0x1p-10"))
    assert_equal(2.6881171418161356e+43, Float("0x1.3494a9b171bf5p+144"))
    assert_equal(-3.720075976020836e-44, Float("-0x1.a8c1f14e2af5dp-145"))
    assert_equal(31.0*2**1019, Float("0x0."+("0"*268)+"1fp2099"))
    assert_equal(31.0*2**1019, Float("0x0."+("0"*600)+"1fp3427"))
    assert_equal(-31.0*2**1019, Float("-0x0."+("0"*268)+"1fp2099"))
    assert_equal(-31.0*2**1019, Float("-0x0."+("0"*600)+"1fp3427"))
    suppress_warning do
      assert_equal(31.0*2**-1027, Float("0x1f"+("0"*268)+".0p-2099"))
      assert_equal(31.0*2**-1027, Float("0x1f"+("0"*600)+".0p-3427"))
      assert_equal(-31.0*2**-1027, Float("-0x1f"+("0"*268)+".0p-2099"))
      assert_equal(-31.0*2**-1027, Float("-0x1f"+("0"*600)+".0p-3427"))
    end

    assert_equal(1.0e10, Float("1.0_"+"00000"*Float::DIG+"e10"))

    z = "0" * (Float::DIG * 4 + 10)
    all_assertions_foreach("long invalid string", "1.0", "1.0e", "1.0e-", "1.0e+") do |n|
      assert_raise(ArgumentError, n += z + "A") {Float(n)}
      assert_raise(ArgumentError, n += z + ".0") {Float(n)}
    end

    x = nil
    2000.times do
      x = Float("0x"+"0"*30)
      break unless x == 0.0
    end
    assert_equal(0.0, x, ->{"%a" % x})
    x = nil
    2000.times do
      begin
        x = Float("0x1."+"0"*270)
      rescue ArgumentError => e
        raise unless /"0x1\.0{270}"/ =~ e.message
      else
        break
      end
    end
    assert_nil(x, ->{"%a" % x})
  end

  def test_divmod
    assert_equal([2, 3.5], 11.5.divmod(4))
    assert_equal([-3, -0.5], 11.5.divmod(-4))
    assert_equal([-3, 0.5], (-11.5).divmod(4))
    assert_equal([2, -3.5], (-11.5).divmod(-4))
    assert_raise(FloatDomainError) { Float::NAN.divmod(2) }
    assert_raise(FloatDomainError) { Float::INFINITY.divmod(2) }
  end

  def test_div
    assert_equal(2, 11.5.div(4))
    assert_equal(-3, 11.5.div(-4))
    assert_equal(-3, (-11.5).div(4))
    assert_equal(2, (-11.5).div(-4))
    assert_raise(FloatDomainError) { 11.5.div(Float::NAN).nan? }
    assert_raise(FloatDomainError) { Float::NAN.div(2).nan? }
    assert_raise(FloatDomainError) { Float::NAN.div(11.5).nan? }
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
    assert_predicate(Float::NAN.remainder(4), :nan?)
    assert_predicate(4.remainder(Float::NAN), :nan?)
  end

  def test_to_s
    inf = Float::INFINITY
    assert_equal("Infinity", inf.to_s)
    assert_equal("-Infinity", (-inf).to_s)
    assert_equal("NaN", (inf / inf).to_s)

    assert_equal("1.0e+18", 1000_00000_00000_00000.0.to_s)

    bug3273 = '[ruby-core:30145]'
    [0.21611564636388508, 0.56].each do |f|
      s = f.to_s
      assert_equal(f, s.to_f, bug3273)
      assert_not_equal(f, s.chop.to_f, bug3273)
    end
  end

  def test_coerce
    assert_equal(Float, 1.0.coerce(1).first.class)
  end

  def test_plus
    assert_equal(4.0, 2.0.send(:+, 2))
    assert_equal(4.0, 2.0.send(:+, (2**32).coerce(2).first))
    assert_equal(4.0, 2.0.send(:+, 2.0))
    assert_equal(Float::INFINITY, 2.0.send(:+, Float::INFINITY))
    assert_predicate(2.0.send(:+, Float::NAN), :nan?)
    assert_raise(TypeError) { 2.0.send(:+, nil) }
  end

  def test_minus
    assert_equal(0.0, 2.0.send(:-, 2))
    assert_equal(0.0, 2.0.send(:-, (2**32).coerce(2).first))
    assert_equal(0.0, 2.0.send(:-, 2.0))
    assert_equal(-Float::INFINITY, 2.0.send(:-, Float::INFINITY))
    assert_predicate(2.0.send(:-, Float::NAN), :nan?)
    assert_raise(TypeError) { 2.0.send(:-, nil) }
  end

  def test_mul
    assert_equal(4.0, 2.0.send(:*, 2))
    assert_equal(4.0, 2.0.send(:*, (2**32).coerce(2).first))
    assert_equal(4.0, 2.0.send(:*, 2.0))
    assert_equal(Float::INFINITY, 2.0.send(:*, Float::INFINITY))
    assert_raise(TypeError) { 2.0.send(:*, nil) }
  end

  def test_div2
    assert_equal(1.0, 2.0.send(:/, 2))
    assert_equal(1.0, 2.0.send(:/, (2**32).coerce(2).first))
    assert_equal(1.0, 2.0.send(:/, 2.0))
    assert_equal(0.0, 2.0.send(:/, Float::INFINITY))
    assert_raise(TypeError) { 2.0.send(:/, nil) }
  end

  def test_modulo2
    assert_equal(0.0, 2.0.send(:%, 2))
    assert_equal(0.0, 2.0.send(:%, (2**32).coerce(2).first))
    assert_equal(0.0, 2.0.send(:%, 2.0))
    assert_raise(TypeError) { 2.0.send(:%, nil) }
  end

  def test_modulo3
    bug6048 = '[ruby-core:42726]'
    assert_equal(4.2, 4.2.send(:%, Float::INFINITY), bug6048)
    assert_equal(4.2, 4.2 % Float::INFINITY, bug6048)
    assert_is_minus_zero(-0.0 % 4.2)
    assert_is_minus_zero(-0.0.send :%, 4.2)
    assert_raise(ZeroDivisionError, bug6048) { 4.2.send(:%, 0.0) }
    assert_raise(ZeroDivisionError, bug6048) { 4.2 % 0.0 }
    assert_raise(ZeroDivisionError, bug6048) { 42.send(:%, 0) }
    assert_raise(ZeroDivisionError, bug6048) { 42 % 0 }
  end

  def test_modulo4
    assert_predicate((0.0).modulo(Float::NAN), :nan?)
    assert_predicate((1.0).modulo(Float::NAN), :nan?)
    assert_predicate(Float::INFINITY.modulo(1), :nan?)
  end

  def test_divmod2
    assert_equal([1.0, 0.0], 2.0.divmod(2))
    assert_equal([1.0, 0.0], 2.0.divmod((2**32).coerce(2).first))
    assert_equal([1.0, 0.0], 2.0.divmod(2.0))
    assert_raise(TypeError) { 2.0.divmod(nil) }

    inf = Float::INFINITY
    assert_raise(ZeroDivisionError) {inf.divmod(0)}

    a, b = (2.0**32).divmod(1.0)
    assert_equal(2**32, a)
    assert_equal(0, b)
  end

  def test_pow
    assert_equal(1.0, 1.0 ** (2**32))
    assert_equal(1.0, 1.0 ** 1.0)
    assert_raise(TypeError) { 1.0 ** nil }
    assert_equal(9.0, 3.0 ** 2)
  end

  def test_eql
    inf = Float::INFINITY
    nan = Float::NAN
    assert_operator(1.0, :eql?, 1.0)
    assert_operator(inf, :eql?, inf)
    assert_not_operator(nan, :eql?, nan)
    assert_not_operator(1.0, :eql?, nil)

    assert_equal(1.0, 1)
    assert_not_equal(1.0, 2**32)
    assert_not_equal(1.0, nan)
    assert_not_equal(1.0, nil)
  end

  def test_cmp
    inf = Float::INFINITY
    nan = Float::NAN
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

    assert_equal(1, inf <=> (Float::MAX.to_i*2))
    assert_equal(-1, -inf <=> (-Float::MAX.to_i*2))
    assert_equal(-1, (Float::MAX.to_i*2) <=> inf)
    assert_equal(1, (-Float::MAX.to_i*2) <=> -inf)

    bug3609 = '[ruby-core:31470]'
    def (pinf = Object.new).infinite?; +1 end
    def (ninf = Object.new).infinite?; -1 end
    def (fin = Object.new).infinite?; nil end
    nonum = Object.new
    assert_equal(0, inf <=> pinf, bug3609)
    assert_equal(1, inf <=> fin, bug3609)
    assert_equal(1, inf <=> ninf, bug3609)
    assert_nil(inf <=> nonum, bug3609)
    assert_equal(-1, -inf <=> pinf, bug3609)
    assert_equal(-1, -inf <=> fin, bug3609)
    assert_equal(0, -inf <=> ninf, bug3609)
    assert_nil(-inf <=> nonum, bug3609)

    assert_raise(ArgumentError) { 1.0 > nil }
    assert_raise(ArgumentError) { 1.0 >= nil }
    assert_raise(ArgumentError) { 1.0 < nil }
    assert_raise(ArgumentError) { 1.0 <= nil }
  end

  def test_zero_p
    assert_predicate(0.0, :zero?)
    assert_not_predicate(1.0, :zero?)
  end

  def test_positive_p
    assert_predicate(+1.0, :positive?)
    assert_not_predicate(+0.0, :positive?)
    assert_not_predicate(-0.0, :positive?)
    assert_not_predicate(-1.0, :positive?)
    assert_predicate(+(0.0.next_float), :positive?)
    assert_not_predicate(-(0.0.next_float), :positive?)
    assert_predicate(Float::INFINITY, :positive?)
    assert_not_predicate(-Float::INFINITY, :positive?)
    assert_not_predicate(Float::NAN, :positive?)
  end

  def test_negative_p
    assert_predicate(-1.0, :negative?)
    assert_not_predicate(-0.0, :negative?)
    assert_not_predicate(+0.0, :negative?)
    assert_not_predicate(+1.0, :negative?)
    assert_predicate(-(0.0.next_float), :negative?)
    assert_not_predicate(+(0.0.next_float), :negative?)
    assert_predicate(-Float::INFINITY, :negative?)
    assert_not_predicate(Float::INFINITY, :negative?)
    assert_not_predicate(Float::NAN, :negative?)
  end

  def test_infinite_p
    inf = Float::INFINITY
    assert_equal(1, inf.infinite?)
    assert_equal(-1, (-inf).infinite?)
    assert_nil(1.0.infinite?)
  end

  def test_finite_p
    inf = Float::INFINITY
    assert_not_predicate(inf, :finite?)
    assert_not_predicate(-inf, :finite?)
    assert_predicate(1.0, :finite?)
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

    inf = Float::INFINITY
    assert_raise(FloatDomainError) { inf.floor }
    assert_raise(FloatDomainError) { inf.ceil }
    assert_raise(FloatDomainError) { inf.round }
    assert_raise(FloatDomainError) { inf.truncate }
  end

  def test_round_with_precision
    assert_equal(1.100, 1.111.round(1))
    assert_equal(1.110, 1.111.round(2))
    assert_equal(11110.0, 11111.1.round(-1))
    assert_equal(11100.0, 11111.1.round(-2))
    assert_equal(-1.100, -1.111.round(1))
    assert_equal(-1.110, -1.111.round(2))
    assert_equal(-11110.0, -11111.1.round(-1))
    assert_equal(-11100.0, -11111.1.round(-2))
    assert_equal(0, 11111.1.round(-5))

    assert_equal(10**300, 1.1e300.round(-300))
    assert_equal(-10**300, -1.1e300.round(-300))
    assert_equal(1.0e-300, 1.1e-300.round(300))
    assert_equal(-1.0e-300, -1.1e-300.round(300))

    bug5227 = '[ruby-core:39093]'
    assert_equal(42.0, 42.0.round(308), bug5227)
    assert_equal(1.0e307, 1.0e307.round(2), bug5227)

    assert_raise(TypeError) {1.0.round("4")}
    assert_raise(TypeError) {1.0.round(nil)}
    def (prec = Object.new).to_int; 2; end
    assert_equal(1.0, 0.998.round(prec))

    assert_equal(+5.02, +5.015.round(2))
    assert_equal(-5.02, -5.015.round(2))
    assert_equal(+1.26, +1.255.round(2))
    assert_equal(-1.26, -1.255.round(2))
  end

  def test_floor_with_precision
    assert_equal(+0.0, +0.001.floor(1))
    assert_equal(-0.1, -0.001.floor(1))
    assert_equal(1.100, 1.111.floor(1))
    assert_equal(1.110, 1.111.floor(2))
    assert_equal(11110, 11119.9.floor(-1))
    assert_equal(11100, 11100.0.floor(-2))
    assert_equal(11100, 11199.9.floor(-2))
    assert_equal(-1.200, -1.111.floor(1))
    assert_equal(-1.120, -1.111.floor(2))
    assert_equal(-11120, -11119.9.floor(-1))
    assert_equal(-11100, -11100.0.floor(-2))
    assert_equal(-11200, -11199.9.floor(-2))
    assert_equal(0, 11111.1.floor(-5))

    assert_equal(10**300, 1.1e300.floor(-300))
    assert_equal(-2*10**300, -1.1e300.floor(-300))
    assert_equal(1.0e-300, 1.1e-300.floor(300))
    assert_equal(-2.0e-300, -1.1e-300.floor(300))

    assert_equal(42.0, 42.0.floor(308))
    assert_equal(1.0e307, 1.0e307.floor(2))

    assert_raise(TypeError) {1.0.floor("4")}
    assert_raise(TypeError) {1.0.floor(nil)}
    def (prec = Object.new).to_int; 2; end
    assert_equal(0.99, 0.998.floor(prec))
  end

  def test_ceil_with_precision
    assert_equal(+0.1, +0.001.ceil(1))
    assert_equal(-0.0, -0.001.ceil(1))
    assert_equal(1.200, 1.111.ceil(1))
    assert_equal(1.120, 1.111.ceil(2))
    assert_equal(11120, 11111.1.ceil(-1))
    assert_equal(11200, 11111.1.ceil(-2))
    assert_equal(-1.100, -1.111.ceil(1))
    assert_equal(-1.110, -1.111.ceil(2))
    assert_equal(-11110, -11111.1.ceil(-1))
    assert_equal(-11100, -11111.1.ceil(-2))
    assert_equal(100000, 11111.1.ceil(-5))

    assert_equal(2*10**300, 1.1e300.ceil(-300))
    assert_equal(-10**300, -1.1e300.ceil(-300))
    assert_equal(2.0e-300, 1.1e-300.ceil(300))
    assert_equal(-1.0e-300, -1.1e-300.ceil(300))

    assert_equal(42.0, 42.0.ceil(308))
    assert_equal(1.0e307, 1.0e307.ceil(2))

    assert_raise(TypeError) {1.0.ceil("4")}
    assert_raise(TypeError) {1.0.ceil(nil)}
    def (prec = Object.new).to_int; 2; end
    assert_equal(0.99, 0.981.ceil(prec))
  end

  def test_truncate_with_precision
    assert_equal(1.100, 1.111.truncate(1))
    assert_equal(1.110, 1.111.truncate(2))
    assert_equal(11110, 11119.9.truncate(-1))
    assert_equal(11100, 11100.0.truncate(-2))
    assert_equal(11100, 11199.9.truncate(-2))
    assert_equal(-1.100, -1.111.truncate(1))
    assert_equal(-1.110, -1.111.truncate(2))
    assert_equal(-11110, -11111.1.truncate(-1))
    assert_equal(-11100, -11111.1.truncate(-2))
    assert_equal(0, 11111.1.truncate(-5))

    assert_equal(10**300, 1.1e300.truncate(-300))
    assert_equal(-10**300, -1.1e300.truncate(-300))
    assert_equal(1.0e-300, 1.1e-300.truncate(300))
    assert_equal(-1.0e-300, -1.1e-300.truncate(300))

    assert_equal(42.0, 42.0.truncate(308))
    assert_equal(1.0e307, 1.0e307.truncate(2))

    assert_raise(TypeError) {1.0.truncate("4")}
    assert_raise(TypeError) {1.0.truncate(nil)}
    def (prec = Object.new).to_int; 2; end
    assert_equal(0.99, 0.998.truncate(prec))
  end

  VS = [
    18446744073709551617.0,
    18446744073709551616.0,
    18446744073709551615.8,
    18446744073709551615.5,
    18446744073709551615.2,
    18446744073709551615.0,
    18446744073709551614.0,

    4611686018427387905.0,
    4611686018427387904.0,
    4611686018427387903.8,
    4611686018427387903.5,
    4611686018427387903.2,
    4611686018427387903.0,
    4611686018427387902.0,

    4294967297.0,
    4294967296.0,
    4294967295.8,
    4294967295.5,
    4294967295.2,
    4294967295.0,
    4294967294.0,

    1073741825.0,
    1073741824.0,
    1073741823.8,
    1073741823.5,
    1073741823.2,
    1073741823.0,
    1073741822.0,

    -1073741823.0,
    -1073741824.0,
    -1073741824.2,
    -1073741824.5,
    -1073741824.8,
    -1073741825.0,
    -1073741826.0,

    -4294967295.0,
    -4294967296.0,
    -4294967296.2,
    -4294967296.5,
    -4294967296.8,
    -4294967297.0,
    -4294967298.0,

    -4611686018427387903.0,
    -4611686018427387904.0,
    -4611686018427387904.2,
    -4611686018427387904.5,
    -4611686018427387904.8,
    -4611686018427387905.0,
    -4611686018427387906.0,

    -18446744073709551615.0,
    -18446744073709551616.0,
    -18446744073709551616.2,
    -18446744073709551616.5,
    -18446744073709551616.8,
    -18446744073709551617.0,
    -18446744073709551618.0,
  ]

  def test_truncate
    VS.each {|f|
      i = f.truncate
      assert_equal(i, f.to_i)
      if f < 0
        assert_operator(i, :<, 0)
      else
        assert_operator(i, :>, 0)
      end
      assert_operator(i.abs, :<=, f.abs)
      d = f.abs - i.abs
      assert_operator(0, :<=, d)
      assert_operator(d, :<, 1)
    }
  end

  def test_ceil
    VS.each {|f|
      i = f.ceil
      if f < 0
        assert_operator(i, :<, 0)
      else
        assert_operator(i, :>, 0)
      end
      assert_operator(i, :>=, f)
      d = f - i
      assert_operator(-1, :<, d)
      assert_operator(d, :<=, 0)
    }
  end

  def test_floor
    VS.each {|f|
      i = f.floor
      if f < 0
        assert_operator(i, :<, 0)
      else
        assert_operator(i, :>, 0)
      end
      assert_operator(i, :<=, f)
      d = f - i
      assert_operator(0, :<=, d)
      assert_operator(d, :<, 1)
    }
  end

  def test_round
    VS.each {|f|
      msg = "round(#{f})"
      i = f.round
      if f < 0
        assert_operator(i, :<, 0, msg)
      else
        assert_operator(i, :>, 0, msg)
      end
      d = f - i
      assert_operator(-0.5, :<=, d, msg)
      assert_operator(d, :<=, 0.5, msg)
    }
  end

  def test_round_half_even
    assert_equal(12.0, 12.5.round(half: :even))
    assert_equal(14.0, 13.5.round(half: :even))

    assert_equal(2.2, 2.15.round(1, half: :even))
    assert_equal(2.2, 2.25.round(1, half: :even))
    assert_equal(2.4, 2.35.round(1, half: :even))

    assert_equal(-2.2, -2.15.round(1, half: :even))
    assert_equal(-2.2, -2.25.round(1, half: :even))
    assert_equal(-2.4, -2.35.round(1, half: :even))

    assert_equal(7.1364, 7.13645.round(4, half: :even))
    assert_equal(7.1365, 7.1364501.round(4, half: :even))
    assert_equal(7.1364, 7.1364499.round(4, half: :even))

    assert_equal(-7.1364, -7.13645.round(4, half: :even))
    assert_equal(-7.1365, -7.1364501.round(4, half: :even))
    assert_equal(-7.1364, -7.1364499.round(4, half: :even))
  end

  def test_round_half_up
    assert_equal(13.0, 12.5.round(half: :up))
    assert_equal(14.0, 13.5.round(half: :up))

    assert_equal(2.2, 2.15.round(1, half: :up))
    assert_equal(2.3, 2.25.round(1, half: :up))
    assert_equal(2.4, 2.35.round(1, half: :up))

    assert_equal(-2.2, -2.15.round(1, half: :up))
    assert_equal(-2.3, -2.25.round(1, half: :up))
    assert_equal(-2.4, -2.35.round(1, half: :up))

    assert_equal(7.1365, 7.13645.round(4, half: :up))
    assert_equal(7.1365, 7.1364501.round(4, half: :up))
    assert_equal(7.1364, 7.1364499.round(4, half: :up))

    assert_equal(-7.1365, -7.13645.round(4, half: :up))
    assert_equal(-7.1365, -7.1364501.round(4, half: :up))
    assert_equal(-7.1364, -7.1364499.round(4, half: :up))
  end

  def test_round_half_down
    assert_equal(12.0, 12.5.round(half: :down))
    assert_equal(13.0, 13.5.round(half: :down))

    assert_equal(2.1, 2.15.round(1, half: :down))
    assert_equal(2.2, 2.25.round(1, half: :down))
    assert_equal(2.3, 2.35.round(1, half: :down))

    assert_equal(-2.1, -2.15.round(1, half: :down))
    assert_equal(-2.2, -2.25.round(1, half: :down))
    assert_equal(-2.3, -2.35.round(1, half: :down))

    assert_equal(7.1364, 7.13645.round(4, half: :down))
    assert_equal(7.1365, 7.1364501.round(4, half: :down))
    assert_equal(7.1364, 7.1364499.round(4, half: :down))

    assert_equal(-7.1364, -7.13645.round(4, half: :down))
    assert_equal(-7.1365, -7.1364501.round(4, half: :down))
    assert_equal(-7.1364, -7.1364499.round(4, half: :down))
  end

  def test_round_half_nil
    assert_equal(13.0, 12.5.round(half: nil))
    assert_equal(14.0, 13.5.round(half: nil))

    assert_equal(2.2, 2.15.round(1, half: nil))
    assert_equal(2.3, 2.25.round(1, half: nil))
    assert_equal(2.4, 2.35.round(1, half: nil))

    assert_equal(-2.2, -2.15.round(1, half: nil))
    assert_equal(-2.3, -2.25.round(1, half: nil))
    assert_equal(-2.4, -2.35.round(1, half: nil))

    assert_equal(7.1365, 7.13645.round(4, half: nil))
    assert_equal(7.1365, 7.1364501.round(4, half: nil))
    assert_equal(7.1364, 7.1364499.round(4, half: nil))

    assert_equal(-7.1365, -7.13645.round(4, half: nil))
    assert_equal(-7.1365, -7.1364501.round(4, half: nil))
    assert_equal(-7.1364, -7.1364499.round(4, half: nil))
  end

  def test_round_half_invalid
    assert_raise_with_message(ArgumentError, /Object/) {
      1.0.round(half: Object)
    }
    assert_raise_with_message(ArgumentError, /xxx/) {
      1.0.round(half: "\0xxx")
    }
    assert_raise_with_message(Encoding::CompatibilityError, /ASCII incompatible/) {
      1.0.round(half: "up".force_encoding("utf-16be"))
    }
  end

  def test_Float
    assert_in_delta(0.125, Float("0.1_2_5"), 0.00001)
    assert_in_delta(0.125, "0.1_2_5__".to_f, 0.00001)
    assert_in_delta(0.0, "0_.125".to_f, 0.00001)
    assert_in_delta(0.0, "0._125".to_f, 0.00001)
    assert_in_delta(0.1, "0.1__2_5".to_f, 0.00001)
    assert_in_delta(0.1, "0.1_e10".to_f, 0.00001)
    assert_in_delta(0.1, "0.1e_10".to_f, 0.00001)
    assert_in_delta(1.0, "0.1e1__0".to_f, 0.00001)
    assert_equal(1, suppress_warning {Float(([1] * 10000).join)}.infinite?)
    assert_not_predicate(Float(([1] * 10000).join("_")), :infinite?) # is it really OK?
    assert_raise(ArgumentError) { Float("1.0\x001") }
    assert_equal(15.9375, Float('0xf.fp0'))
    assert_raise(ArgumentError) { Float('0x') }
    assert_equal(15, Float('0xf'))
    assert_equal(15, Float('0xfp0'))
    assert_raise(ArgumentError) { Float('0xfp') }
    assert_raise(ArgumentError) { Float('0xf.') }
    assert_raise(ArgumentError) { Float('0xf.p') }
    assert_raise(ArgumentError) { Float('0xf.p0') }
    assert_raise(ArgumentError) { Float('0xf.f') }
    assert_raise(ArgumentError) { Float('0xf.fp') }
    begin
      verbose_bak, $VERBOSE = $VERBOSE, nil
      assert_equal(Float::INFINITY, Float('0xf.fp1000000000000000'))
    ensure
      $VERBOSE = verbose_bak
    end
    assert_equal(1, suppress_warning {Float("1e10_00")}.infinite?)
    assert_raise(TypeError) { Float(nil) }
    assert_raise(TypeError) { Float(:test) }
    o = Object.new
    def o.to_f; inf = Float::INFINITY; inf/inf; end
    assert_predicate(Float(o), :nan?)
  end

  def test_invalid_str
    bug4310 = '[ruby-core:34820]'
    assert_raise(ArgumentError, bug4310) {under_gc_stress {Float('a'*10000)}}
  end

  def test_Float_with_invalid_exception
    assert_raise(ArgumentError) {
      Float("0", exception: 1)
    }
  end

  def test_Float_with_exception_keyword
    assert_raise(ArgumentError) {
      Float(".", exception: true)
    }
    assert_nothing_raised(ArgumentError) {
      assert_equal(nil, Float(".", exception: false))
    }
    assert_raise(RangeError) {
      Float(1i, exception: true)
    }
    assert_nothing_raised(RangeError) {
      assert_equal(nil, Float(1i, exception: false))
    }
    assert_raise(TypeError) {
      Float(nil, exception: true)
    }
    assert_nothing_raised(TypeError) {
      assert_equal(nil, Float(nil, exception: false))
    }
    assert_nothing_raised(TypeError) {
      assert_equal(nil, Float(:test, exception: false))
    }
    assert_nothing_raised(TypeError) {
      assert_equal(nil, Float(Object.new, exception: false))
    }
    assert_nothing_raised(TypeError) {
      o = Object.new
      def o.to_f; 3.14; end
      assert_equal(3.14, Float(o, exception: false))
    }
    assert_nothing_raised(RuntimeError) {
      o = Object.new
      def o.to_f; raise; end
      assert_equal(nil, Float(o, exception: false))
    }
  end

  def test_num2dbl
    assert_raise(ArgumentError, "comparison of String with 0 failed") do
      1.0.step(2.0, "0.5") {}
    end
    assert_raise(TypeError) do
      1.0.step(2.0, nil) {}
    end
  end

  def test_sleep_with_Float
    assert_nothing_raised("[ruby-core:23282]") do
      sleep(0.1+0.1+0.1+0.1+0.1+0.1+0.1+0.1+0.1+0.1)
    end
  end

  def test_step
    1000.times do
      a = rand
      b = a+rand*1000
      s = (b - a) / 10
      assert_equal(11, (a..b).step(s).to_a.length)
    end

    (1.0..12.7).step(1.3).each do |n|
      assert_operator(n, :<=, 12.7)
    end

    assert_equal([5.0, 4.0, 3.0, 2.0], 5.0.step(1.5, -1).to_a)

    assert_equal(11, ((0.24901079128550474)..(340.2500808898068)).step(34.00010700985213).to_a.size)
    assert_equal(11, ((0.24901079128550474)..(340.25008088980684)).step(34.00010700985213).to_a.size)
    assert_equal(11, ((-0.24901079128550474)..(-340.2500808898068)).step(-34.00010700985213).to_a.size)
    assert_equal(11, ((-0.24901079128550474)..(-340.25008088980684)).step(-34.00010700985213).to_a.size)
  end

  def test_step2
    assert_equal([0.0], 0.0.step(1.0, Float::INFINITY).to_a)
  end

  def test_step_excl
    1000.times do
      a = rand
      b = a+rand*1000
      s = (b - a) / 10
      b = a + s*9.999999
      seq = (a...b).step(s)
      assert_equal(10, seq.to_a.length, seq.inspect)
    end

    assert_equal([1.0, 2.9, 4.8, 6.699999999999999], (1.0...6.8).step(1.9).to_a)

    e = 1+1E-12
    (1.0 ... e).step(1E-16) do |n|
      assert_operator(n, :<=, e)
    end

    assert_equal(10, ((0.24901079128550474)...(340.2500808898068)).step(34.00010700985213).to_a.size)
    assert_equal(11, ((0.24901079128550474)...(340.25008088980684)).step(34.00010700985213).to_a.size)
    assert_equal(10, ((-0.24901079128550474)...(-340.2500808898068)).step(-34.00010700985213).to_a.size)
    assert_equal(11, ((-0.24901079128550474)...(-340.25008088980684)).step(-34.00010700985213).to_a.size)
  end

  def test_singleton_method
    # flonum on 64bit platform
    assert_raise(TypeError) { a = 1.0; def a.foo; end }
    # always not flonum
    assert_raise(TypeError) { a = Float::INFINITY; def a.foo; end }
  end

  def test_long_string
    assert_separately([], <<-'end;')
    assert_in_epsilon(10.0, ("1."+"1"*300000).to_f*9)
    end;
  end

  def test_next_float
    smallest = 0.0.next_float
    assert_equal(-Float::MAX, (-Float::INFINITY).next_float)
    assert_operator(-Float::MAX, :<, (-Float::MAX).next_float)
    assert_equal(Float::EPSILON/2, (-1.0).next_float + 1.0)
    assert_operator(0.0, :<, smallest)
    assert_operator([0.0, smallest], :include?, smallest/2)
    assert_equal(Float::EPSILON, 1.0.next_float - 1.0)
    assert_equal(Float::INFINITY, Float::MAX.next_float)
    assert_equal(Float::INFINITY, Float::INFINITY.next_float)
    assert_predicate(Float::NAN.next_float, :nan?)
  end

  def test_prev_float
    smallest = 0.0.next_float
    assert_equal(-Float::INFINITY, (-Float::INFINITY).prev_float)
    assert_equal(-Float::INFINITY, (-Float::MAX).prev_float)
    assert_equal(-Float::EPSILON, (-1.0).prev_float + 1.0)
    assert_equal(-smallest, 0.0.prev_float)
    assert_operator([0.0, 0.0.prev_float], :include?, 0.0.prev_float/2)
    assert_equal(-Float::EPSILON/2, 1.0.prev_float - 1.0)
    assert_operator(Float::MAX, :>, Float::MAX.prev_float)
    assert_equal(Float::MAX, Float::INFINITY.prev_float)
    assert_predicate(Float::NAN.prev_float, :nan?)
  end

  def test_next_prev_float_zero
    z = 0.0.next_float.prev_float
    assert_equal(0.0, z)
    assert_equal(Float::INFINITY, 1.0/z)
    z = 0.0.prev_float.next_float
    assert_equal(0.0, z)
    assert_equal(-Float::INFINITY, 1.0/z)
  end

  def test_hash_0
    bug10979 = '[ruby-core:68541] [Bug #10979]'
    assert_equal(+0.0.hash, -0.0.hash)
    assert_operator(+0.0, :eql?, -0.0)
    h = {0.0 => bug10979}
    assert_equal(bug10979, h[-0.0])
  end

  def test_aliased_quo_recursion
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      class Float
        $VERBOSE = nil
        alias / quo
      end
      assert_raise(NameError) do
        begin
          1.0/2.0
        rescue SystemStackError => e
          raise SystemStackError, e.message
        end
      end
    end;
  end
end
