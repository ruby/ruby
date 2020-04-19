require_relative "test_helper"

class ComplexTest < StdlibTest
  target Complex
  using hook.refinement

  def test_singleton_polar
    Complex.polar(10)
    Complex.polar(3, 0)
    Complex.polar(3, Math::PI)
    Complex.polar(3, Complex.rect(1))
  end

  def test_rect
    Complex.rect(10, 20)
    Complex.rect(Complex.polar(1), Complex.rect(1))

    Complex.rectangular(10, 20)
  end

  def test_calc
    c = Complex.rect(10, 4)

    c * 3
    c * 2.1
    c * 4r
    c * c

    c ** 2
    c ** 2.0
    c ** 3r
    c ** c

    c + 1
    c + 1.2
    c + 3r
    c + c

    c - 1
    c - 1.2
    c - 3r
    c - c

    c / 1
    c / 1.2
    c / 3r
    c / c
  end

  def test_compare
    c = Complex.rect(3,2)

    c <=> 1
  end

  def test_eq
    a = Complex.rect(1,2)

    a == 1
    a == Object.new
  end

  def test_abs
    a = Complex.rect(1,2)

    a.abs
    a.abs2
  end

  def test_angle
    a = Complex.rect(1,2)

    a.angle
    a.arg
    a.phase
  end

  def test_conj
    a = Complex.rect(1,2)

    a.conj
    a.conjugate
  end

  def test_denominator
    a = Complex.rect(1.11,2r)

    a.denominator
  end

  def test_fdiv
    a = Complex.rect(1.11,2r)

    a.fdiv(3)
    a.fdiv(3.1)
    a.fdiv(1r/3)
    a.fdiv(a)
  end

  def test_imag
    a = Complex.rect(1.11,2r)

    a.imag
    a.imaginary
  end

  def test_numerator
    a = Complex.rect(1.11, 2r)

    a.numerator
  end

  def test_instance_polar
    Complex.rect(1.11, 2r).polar
    Complex.polar(1.11, 2r).polar
  end

  def test_quo
    a = Complex.rect(1.11, 2r)

    a.quo(3)
    a.quo(1.3)
    a.quo(1r/3)
    a.quo(Complex.rect(1,2))
  end

  def test_rationalize
    a = Complex.rect(1.11, 0)

    a.rationalize
    a.rationalize(3.11)
  end
end
