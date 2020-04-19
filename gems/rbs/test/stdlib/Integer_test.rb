require_relative "test_helper"

class IntegerTest < StdlibTest
  target Integer
  using hook.refinement

  def test_sqrt
    Integer.sqrt(4)
    Integer.sqrt(4.0)
    Integer.sqrt(4/1r)
    Integer.sqrt(ToInt.new)
  end

  def test_modulo
    3 % 1
    3 % 1.1
    3 % 1.5r
  end

  def test_bitwise_ops
    3 & 1
    1 ^ 3
  end

  def test_calc
    3 * 1
    3 * 1.0
    3 * (1r/3)

    3 - 1
    3 - 0.1
    3 - 1r
    3 - 1.to_c

    1 ** 1
    2 ** 2.1
    3 ** 3r
    3 ** 10.to_c

    3 + 1
    3 + 1.0
    3 + (1r/3)
    3 + 10.to_c

    3 / 1
    3 / 1.0
    3 / (1r/3)
    30 / 10.to_c
  end

  def test_compare
    3 < 1
    3 < 1.0
    3 < 1r

    1 > 1
    1 > 1.0
    1 > 1r

    1 <= 3
    1 <= 1.3
    1 <= 3r

    1 >= 3
    1 >= 1.3
    1 >= 3r

    1 <=> 1
    1 <=> 1.0
    1 <=> 3r

    3 === 3.0
    3 === ""
  end

  def test_shift
    1 << 30
    1 << 30.to_f
    1 << ToInt.new

    1 >> 30
    1 >> 30.to_f
    1 >> ToInt.new
  end

  def test_aref
    3[0]
    3[0.3]
    3[ToInt.new]

    3[1,2]
    3[1...3]
  end

  def test_to_s
    1.to_s
    1.to_s(2)
    1.to_s(3)
    1.to_s(4)
    1.to_s(5)
    1.to_s(6)
    1.to_s(7)
    1.to_s(8)
    1.to_s(9)
    1.to_s(10)
    1.to_s(11)
    1.to_s(12)
    1.to_s(13)
    1.to_s(14)
    1.to_s(15)
    1.to_s(16)
    1.to_s(17)
    1.to_s(18)
    1.to_s(19)
    1.to_s(20)
    1.to_s(21)
    1.to_s(22)
    1.to_s(23)
    1.to_s(24)
    1.to_s(25)
    1.to_s(26)
    1.to_s(27)
    1.to_s(28)
    1.to_s(29)
    1.to_s(30)
    1.to_s(31)
    1.to_s(32)
    1.to_s(33)
    1.to_s(34)
    1.to_s(35)
    1.to_s(36)
    30.to_s(ToInt.new)
  end

  def test_abs_abs2
    3.abs
    3.abs2
  end

  def test_allbits?
    1.allbits?(1)
    2.allbits?(1)
    3.allbits?(ToInt.new)
  end

  def test_angle
    3.angle()
  end

  def test_anybits?
    0xf0.anybits?(0xf)
    0xf1.anybits?(0xf)
    0xf1.anybits?(ToInt.new)
  end

  def test_arg
    3.arg
  end

  def test_bit_length
    3.bit_length
  end

  def test_ceil
    3.ceil
    3.ceil(10)
    3.ceil(ToInt.new)
  end

  def test_chr
    3.chr
    3.chr(Encoding::UTF_8)
    3.chr("UTF-7")
    3.chr(ToStr.new("ASCII-8BIT"))
  end

  def test_conj
    3.conj
  end

  def test_conjugate
    3.conjugate
  end

  def test_denominator
    3.denominator
  end

  def test_digits
    3.digits
    3.digits(3)
    3.digits(3.0)
    30.digits(ToInt.new)
  end

  def test_div
    30.div(10)
  end

  def test_div_mod
    3.divmod(3)
    40.divmod(1.0)
    30.divmod(30r)
  end

  def test_down_to
    30.downto(1) {}
    30.downto(31)
  end

  def test_eql?
    1.eql?("")
    3.eql?(1.0)
  end

  def test_even?
    30.even?
  end

  def test_fdiv
    30.fdiv(30)
    30.fdiv(3r)
    30.fdiv(3.1)
  end

  def test_finite?
    30.finite?
  end

  def test_floor
    30.floor
    30.floor(3)
    30.floor(ToInt.new)
  end

  def test_gcd
    30.gcd(1)
  end

  def test_gcdlcm
    30.gcdlcm(31)
  end

  def test_infinite?
    30.infinite?
  end

  def test_lcm
    30.lcm(50)
  end

  def test_magnitude
    30.magnitude
  end

  def test_modulo_
    30.modulo(30)
    30.modulo(3.1)
    30.modulo(3r/5)
  end

  def test_next
    30.next
  end

  def test_nobits?
    0xf0.nobits?(0xf)
    0xf1.nobits?(0xf)
    30.nobits?(ToInt.new)
  end

  def test_nonzero?
    30.nonzero?
    0.nonzero?
  end

  def test_numerator
    30.numerator
  end

  def test_pow
    1.pow(30)
    1.pow(2.0)
    1.pow(30.to_c)
    3.pow(3, 5)
  end

  def test_quo
    3.quo(1)
    3.quo(2.1)
    3.quo(4r/5)
    3.quo(10.to_c)
  end

  def test_rationalize
    3.rationalize
    3.rationalize(30)
  end

  def test_remainder
    3.remainder(1)
    3.remainder(1.3)
    3.remainder(1r/3)
  end

  def test_round
    13.round()
    13.round(half: :up)
    14.round(-1, half: :down)
    15.round(ToInt.new)
  end

  def test_step
    3.step { break }
    3.step
    3.step(10, 2) {}
    3.step(10, 2)
    3.step(10, 1.1) {}
    3.step(10, 1.1)

    3.step(to: 30) { break }
    3.step(to: 30)
    3.step(to: 30, by: 100) {}
    3.step(to: 30, by: 100)
    3.step(to: 30, by: 10.0) {}
    3.step(to: 30, by: 10.0)
  end

  def test_times
    3.times {}
    3.times
  end

  def test_truncate
    100.truncate
    100.truncate(10)
    100.truncate(ToInt.new(-2))
  end

  def test_upto
    5.upto(10) {}
  end
end
