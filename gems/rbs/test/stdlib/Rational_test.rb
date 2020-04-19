require_relative "test_helper"

class RationalTest < StdlibTest
  target Rational
  using hook.refinement

  def test_calc
    10r % 10
    10r % 1.3
    10r % 2r

    10r * 10
    10r * 1.2
    10r * 2r
    10r * Complex.rect(1,2)

    3r ** 2
    3r ** 2.1
    3r ** 2r
    3r ** Complex.rect(1,2)

    10r + 10
    10r + 1.2
    10r + 2r
    10r + Complex.rect(1,2)

    10r - 10
    10r - 1.2
    10r - 2r
    10r - Complex.rect(1,2)

    10r / 10
    10r / 1.2
    10r / 2r
    10r / Complex.rect(1,2)
  end

  def test_compare
    10r <=> 1
    10r < 1
    10r <= 3r
    10r > 3.1
    10r >= Complex.rect(1,0)
  end

  def test_eq
    a = 31r

    a == 1
    a == Object.new
  end

  def test_abs
    a = 31r

    a.abs
    a.abs2
  end

  def test_angle
    a = 31r

    a.angle
    a.arg
    -a.phase
  end

  def test_ceil
    a = 312r/5

    a.ceil
    a.ceil(3)
    # a.ceil(ToInt.new) # does not accept to_int
  end

  def test_conj
    a = 312r

    a.conj
    a.conjugate
  end

  def test_denominator
    a = 133r

    a.denominator
  end

  def test_div
    a = 123r

    a.div(3)
    a.div(3.1)
    a.div(12r)

    a.divmod(3)
    a.divmod(3.1)
    a.divmod(1r/5)
  end

  def test_fdiv
    a = 3r/2

    a.fdiv(3)
    a.fdiv(3.1)
    a.fdiv(1r/3)
  end

  def test_floor
    a = 3r/2

    a.floor()
    a.floor(-1)
    # a.floor(ToInt.new) # No to_int support
  end

  def test_modulo
    a = 3r/2

    a.modulo(2)
    a.modulo(1.1)
    a.modulo(a)
  end

  def test_numerator
    a = 3r/2

    a.numerator
  end

  def test_polar
    31r.polar
    (-31r/2).polar
  end

  def test_quo
    a = 1/11r

    a.quo(3)
    a.quo(1.3)
    a.quo(1r/3)
    a.quo(Complex.rect(1,2))
  end

  def test_rationalize
    a = 14r

    a.rationalize
    a.rationalize(3.11)
  end

  def test_reminder
    a = 14r

    a.remainder(3)
    a.remainder(3.1)
    a.remainder(3r/5)
  end

  def test_round
    a = 1r/3

    a.round(half: :up)
    a.round(2, half: :up)
    # a.round(ToInt.new(-2), half: :up) # to_int not supported
  end

  def test_step
    a = 1r/3

    a.step { break }
    a.step(1, 2) { }
    a.step(by: 3, to: 100) { }
  end

  def test_truncate
    a = 1r/3

    a.truncate
    a.truncate(1)
  end
end
