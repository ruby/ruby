require_relative "test_helper"

class FloatTest < StdlibTest
  target Float
  using hook.refinement

  def test_calc
    10.0 % 3
    10.0 % 3.1
    10.0 % 3r

    3.0 * 1
    3.0 * 1.1
    3.0 * Complex.rect(1,2)
    3.0 * 2r

    3.1 ** 2
    3.1 ** 1.2
    3.1 ** Complex.rect(1,2)
    3.1 ** 2r

    3.0 + 1
    3.0 + 1.1
    3.0 + 2r
    3.0 + Complex.rect(1,2)

    3.0 - 1
    3.0 - 1.1
    3.0 - 2r
    3.0 - Complex.rect(1,2)

    3.0 / 1
    3.0 / 1.1
    3.0 / 2r
    3.0 / Complex.rect(1,2)
  end

  def test_compare
    1.0 <=> 1
    1.0 < 1
    1.0 <= 3r
    1.0 > 3.1
  end

  def test_eq
    a = 1.0

    a == 1
    a == Object.new

    a === 1
    a === Object.new
  end

  def test_abs
    a = 3.1

    a.abs
    a.abs2
  end

  def test_angle
    a = 3.1

    a.angle
    a.arg
    -a.phase
  end

  def test_ceil
    a = 31.2

    a.ceil
    a.ceil(3)
    a.ceil(ToInt.new)
  end

  def test_conj
    a = 31.4

    a.conj
    a.conjugate
  end

  def test_denominator
    a = 13.3

    a.denominator
  end

  def test_div
    a = 12.3

    a.div(3)
    a.div(3.1)
    a.div(12r)

    a.divmod(3)
    a.divmod(3.1)
    a.divmod(1r/5)
  end

  def test_fdiv
    a = 3.2

    a.fdiv(3)
    a.fdiv(3.1)
    a.fdiv(1r/3)
    a.fdiv(Complex.rect(1,2))
  end

  def test_floor
    a = 3.2

    a.floor()
    a.floor(-1)
    a.floor(ToInt.new) # No to_int support
  end

  def test_modulo
    a = 3.2

    a.modulo(2)
    a.modulo(1.1)
    a.modulo(a)
  end

  def test_numerator
    a = 3.2

    a.numerator
  end

  def test_polar
    3.1.polar
    (-3.12).polar
  end

  def test_quo
    a = 1.11

    a.quo(3)
    a.quo(1.3)
    a.quo(1r/3)
    a.quo(Complex.rect(1,2))
  end

  def test_rationalize
    a = 1.22232.next_float

    a.rationalize
    a.rationalize(3.11)
  end

  def test_reminder
    a = 1.4

    a.remainder(3)
    a.remainder(3.1)
    a.remainder(3r/5)
  end

  def test_round
    a = 1.3

    a.round(half: :up)
    a.round(2, half: :up)
    a.round(ToInt.new(-2), half: :up)
  end

  def test_step
    a = 1.3

    a.step { break }
    a.step(1, 2) { }
    a.step(by: 3, to: 100) { }
  end

  def test_to_s
    a = 1.3

    a.to_s
  end

  def test_truncate
    a = 1.3

    a.truncate
    a.truncate(1)
  end
end
