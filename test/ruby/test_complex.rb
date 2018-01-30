# frozen_string_literal: false
require 'test/unit'

class ComplexSub < Complex; end

class Complex_Test < Test::Unit::TestCase

  def test_rationalize
    assert_equal(1.quo(3), Complex(1/3.0, 0).rationalize, '[ruby-core:38885]')
    assert_equal(1.quo(5), Complex(0.2, 0).rationalize, '[ruby-core:38885]')
    assert_equal(5.quo(2), Complex(2.5, 0).rationalize(0), '[ruby-core:40667]')
  end

  def test_compsub
    c = ComplexSub.__send__(:convert, 1)

    assert_kind_of(Numeric, c)

    assert_instance_of(ComplexSub, c)

    c2 = c + 1
    assert_instance_of(ComplexSub, c2)
    c2 = c - 1
    assert_instance_of(ComplexSub, c2)

    c3 = c - c2
    assert_instance_of(ComplexSub, c3)

    s = Marshal.dump(c)
    c5 = Marshal.load(s)
    assert_equal(c, c5)
    assert_instance_of(ComplexSub, c5)

    c1 = Complex(1)
    assert_equal(c1.hash, c.hash, '[ruby-dev:38850]')
    assert_equal([true, true], [c.eql?(c1), c1.eql?(c)])
  end

  def test_eql_p
    c = Complex(0)
    c2 = Complex(0)
    c3 = Complex(1)

    assert_operator(c, :eql?, c2)
    assert_not_operator(c, :eql?, c3)

    assert_not_operator(c, :eql?, 0)
  end

  def test_hash
    h = Complex(1,2).hash
    assert_kind_of(Integer, h)
    assert_nothing_raised {h.to_s}
    h = Complex(1.0,2.0).hash
    assert_kind_of(Integer, h)
    assert_nothing_raised {h.to_s}

    h = {}
    h[Complex(0)] = 0
    h[Complex(0,1)] = 1
    h[Complex(1,0)] = 2
    h[Complex(1,1)] = 3

    assert_equal(4, h.size)
    assert_equal(2, h[Complex(1,0)])

    h[Complex(0,0)] = 9
    assert_equal(4, h.size)

    h[Complex(0.0,0.0)] = 9.0
    assert_equal(5, h.size)

    if (0.0/0).nan? && !((0.0/0).eql?(0.0/0))
      h = {}
      3.times{h[Complex(0.0/0)] = 1}
      assert_equal(3, h.size)
    end
  end

  def test_freeze
    c = Complex(1)
    assert_predicate(c, :frozen?)
    assert_instance_of(String, c.to_s)
  end

  def test_conv
    c = Complex(0,0)
    assert_equal(Complex(0,0), c)

    c = Complex(2**32, 2**32)
    assert_equal(Complex(2**32,2**32), c)
    assert_equal([2**32,2**32], [c.real,c.imag])

    c = Complex(-2**32, 2**32)
    assert_equal(Complex(-2**32,2**32), c)
    assert_equal([-2**32,2**32], [c.real,c.imag])

    c = Complex(2**32, -2**32)
    assert_equal(Complex(2**32,-2**32), c)
    assert_equal([2**32,-2**32], [c.real,c.imag])

    c = Complex(-2**32, -2**32)
    assert_equal(Complex(-2**32,-2**32), c)
    assert_equal([-2**32,-2**32], [c.real,c.imag])

    c = Complex(Complex(1,2),2)
    assert_equal(Complex(1,4), c)

    c = Complex(2,Complex(1,2))
    assert_equal(Complex(0,1), c)

    c = Complex(Complex(1,2),Complex(1,2))
    assert_equal(Complex(-1,3), c)

    c = Complex::I
    assert_equal(Complex(0,1), c)

    assert_equal(Complex(1),Complex(1))
    assert_equal(Complex(1),Complex('1'))
    assert_equal(Complex(3.0,3.0),Complex('3.0','3.0'))
    assert_equal(Complex(1,1),Complex('3/3','3/3'))
    assert_raise(TypeError){Complex(nil)}
    assert_raise(TypeError){Complex(Object.new)}
    assert_raise(ArgumentError){Complex()}
    assert_raise(ArgumentError){Complex(1,2,3)}

    if (0.0/0).nan?
      assert_nothing_raised{Complex(0.0/0)}
    end
    if (1.0/0).infinite?
      assert_nothing_raised{Complex(1.0/0)}
    end
  end

  def test_attr
    c = Complex(4)

    assert_equal(4, c.real)
    assert_equal(0, c.imag)

    c = Complex(4,5)

    assert_equal(4, c.real)
    assert_equal(5, c.imag)

    if -0.0.to_s == '-0.0'
      c = Complex(-0.0,-0.0)

      assert_equal('-0.0', c.real.to_s)
      assert_equal('-0.0', c.imag.to_s)
    end

    c = Complex(4)

    assert_equal(4, c.real)
    assert_equal(0, c.imag)
    assert_equal(c.imag, c.imaginary)

    c = Complex(4,5)

    assert_equal(4, c.real)
    assert_equal(5, c.imag)
    assert_equal(c.imag, c.imaginary)

    if -0.0.to_s == '-0.0'
      c = Complex(-0.0,-0.0)

      assert_equal('-0.0', c.real.to_s)
      assert_equal('-0.0', c.imag.to_s)
      assert_equal(c.imag.to_s, c.imaginary.to_s)
    end

    c = Complex(4)

    assert_equal(4, c.real)
    assert_equal(c.imag, c.imaginary)
    assert_equal(0, c.imag)

    c = Complex(4,5)

    assert_equal(4, c.real)
    assert_equal(5, c.imag)
    assert_equal(c.imag, c.imaginary)

    c = Complex(-0.0,-0.0)

    assert_equal('-0.0', c.real.to_s)
    assert_equal('-0.0', c.imag.to_s)
    assert_equal(c.imag.to_s, c.imaginary.to_s)
  end

  def test_attr2
    c = Complex(1)

    assert_not_predicate(c, :integer?)
    assert_not_predicate(c, :real?)

    assert_predicate(Complex(0), :zero?)
    assert_predicate(Complex(0,0), :zero?)
    assert_not_predicate(Complex(1,0), :zero?)
    assert_not_predicate(Complex(0,1), :zero?)
    assert_not_predicate(Complex(1,1), :zero?)

    assert_equal(nil, Complex(0).nonzero?)
    assert_equal(nil, Complex(0,0).nonzero?)
    assert_equal(Complex(1,0), Complex(1,0).nonzero?)
    assert_equal(Complex(0,1), Complex(0,1).nonzero?)
    assert_equal(Complex(1,1), Complex(1,1).nonzero?)
  end

  def test_rect
    assert_equal([1,2], Complex.rectangular(1,2).rectangular)
    assert_equal([1,2], Complex.rect(1,2).rect)
  end

  def test_polar
    assert_equal([1,2], Complex.polar(1,2).polar)
    assert_equal(Complex.polar(1.0, Math::PI * 2 / 3), Complex.polar(1, Math::PI * 2 / 3))
  end

  def test_uplus
    assert_equal(Complex(1), +Complex(1))
    assert_equal(Complex(-1), +Complex(-1))
    assert_equal(Complex(1,1), +Complex(1,1))
    assert_equal(Complex(-1,1), +Complex(-1,1))
    assert_equal(Complex(1,-1), +Complex(1,-1))
    assert_equal(Complex(-1,-1), +Complex(-1,-1))

    if -0.0.to_s == '-0.0'
      c = +Complex(0.0,0.0)
      assert_equal('0.0', c.real.to_s)
      assert_equal('0.0', c.imag.to_s)

      c = +Complex(-0.0,-0.0)
      assert_equal('-0.0', c.real.to_s)
      assert_equal('-0.0', c.imag.to_s)
    end
  end

  def test_negate
    assert_equal(Complex(-1), -Complex(1))
    assert_equal(Complex(1), -Complex(-1))
    assert_equal(Complex(-1,-1), -Complex(1,1))
    assert_equal(Complex(1,-1), -Complex(-1,1))
    assert_equal(Complex(-1,1), -Complex(1,-1))
    assert_equal(Complex(1,1), -Complex(-1,-1))

    if -0.0.to_s == '-0.0'
      c = -Complex(0.0,0.0)
      assert_equal('-0.0', c.real.to_s)
      assert_equal('-0.0', c.imag.to_s)

      c = -Complex(-0.0,-0.0)
      assert_equal('0.0', c.real.to_s)
      assert_equal('0.0', c.imag.to_s)
    end
  end

  def test_add
    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(3,5), c + c2)

    assert_equal(Complex(3,2), c + 2)
    assert_equal(Complex(3.0,2), c + 2.0)

    assert_equal(Complex(Rational(3,1),Rational(2)), c + Rational(2))
    assert_equal(Complex(Rational(5,3),Rational(2)), c + Rational(2,3))
  end

  def test_sub
    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(-1,-1), c - c2)

    assert_equal(Complex(-1,2), c - 2)
    assert_equal(Complex(-1.0,2), c - 2.0)

    assert_equal(Complex(Rational(-1,1),Rational(2)), c - Rational(2))
    assert_equal(Complex(Rational(1,3),Rational(2)), c - Rational(2,3))
  end

  def test_mul
    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(-4,7), c * c2)

    assert_equal(Complex(2,4), c * 2)
    assert_equal(Complex(2.0,4.0), c * 2.0)

    assert_equal(Complex(Rational(2,1),Rational(4)), c * Rational(2))
    assert_equal(Complex(Rational(2,3),Rational(4,3)), c * Rational(2,3))

    c = Complex(Float::INFINITY, 0)
    assert_equal(Complex(Float::INFINITY, 0), c * Complex(1, 0))
    assert_equal(Complex(0, Float::INFINITY), c * Complex(0, 1))
    c = Complex(0, Float::INFINITY)
    assert_equal(Complex(0, Float::INFINITY), c * Complex(1, 0))
    assert_equal(Complex(-Float::INFINITY, 0), c * Complex(0, 1))
  end

  def test_div
    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(Rational(8,13),Rational(1,13)), c / c2)

    c = Complex(1.0,2.0)
    c2 = Complex(2.0,3.0)

    r = c / c2
    assert_in_delta(0.615, r.real, 0.001)
    assert_in_delta(0.076, r.imag, 0.001)

    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(Rational(1,2),1), c / 2)
    assert_equal(Complex(0.5,1.0), c / 2.0)

    assert_equal(Complex(Rational(1,2),Rational(1)), c / Rational(2))
    assert_equal(Complex(Rational(3,2),Rational(3)), c / Rational(2,3))
  end

  def test_quo
    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(Rational(8,13),Rational(1,13)), c.quo(c2))

    c = Complex(1.0,2.0)
    c2 = Complex(2.0,3.0)

    r = c.quo(c2)
    assert_in_delta(0.615, r.real, 0.001)
    assert_in_delta(0.076, r.imag, 0.001)

    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(Rational(1,2),1), c.quo(2))
    assert_equal(Complex(0.5,1.0), c.quo(2.0))

    assert_equal(Complex(Rational(1,2),Rational(1)), c / Rational(2))
    assert_equal(Complex(Rational(3,2),Rational(3)), c / Rational(2,3))
  end

  def test_fdiv
    c = Complex(1,2)
    c2 = Complex(2,3)

    r = c.fdiv(c2)
    assert_in_delta(0.615, r.real, 0.001)
    assert_in_delta(0.076, r.imag, 0.001)

    c = Complex(1.0,2.0)
    c2 = Complex(2.0,3.0)

    r = c.fdiv(c2)
    assert_in_delta(0.615, r.real, 0.001)
    assert_in_delta(0.076, r.imag, 0.001)

    c = Complex(1,2)
    c2 = Complex(2,3)

    assert_equal(Complex(0.5,1.0), c.fdiv(2))
    assert_equal(Complex(0.5,1.0), c.fdiv(2.0))
  end

  def test_expt
    c = Complex(1,2)
    c2 = Complex(2,3)

    r = c ** c2
    assert_in_delta(-0.015, r.real, 0.001)
    assert_in_delta(-0.179, r.imag, 0.001)

    assert_equal(Complex(-3,4), c ** 2)
    assert_equal(Complex(Rational(-3,25),Rational(-4,25)), c ** -2)

    r = c ** 2.0
    assert_in_delta(-3.0, r.real, 0.001)
    assert_in_delta(4.0, r.imag, 0.001)

    r = c ** -2.0
    assert_in_delta(-0.12, r.real, 0.001)
    assert_in_delta(-0.16, r.imag, 0.001)

    assert_equal(Complex(-3,4), c ** Rational(2))
    assert_equal(Complex(Rational(-3,25),Rational(-4,25)),
      c ** Rational(-2)) # why failed?

    r = c ** Rational(2,3)
    assert_in_delta(1.264, r.real, 0.001)
    assert_in_delta(1.150, r.imag, 0.001)

    r = c ** Rational(-2,3)
    assert_in_delta(0.432, r.real, 0.001)
    assert_in_delta(-0.393, r.imag, 0.001)
  end

  def test_cmp
    assert_raise(NoMethodError){1 <=> Complex(1,1)}
    assert_raise(NoMethodError){Complex(1,1) <=> 1}
    assert_raise(NoMethodError){Complex(1,1) <=> Complex(1,1)}
  end

  def test_eqeq
    assert_equal(Complex(1), Complex(1,0))
    assert_equal(Complex(-1), Complex(-1,0))

    assert_not_equal(Complex(1), Complex(2,1))
    assert_operator(Complex(2,1), :!=, Complex(1))
    assert_not_equal(nil, Complex(1))
    assert_not_equal('', Complex(1))

    nan = 0.0 / 0
    if nan.nan? && nan != nan
      assert_not_equal(Complex(nan, 0), Complex(nan, 0))
      assert_not_equal(Complex(0, nan), Complex(0, nan))
      assert_not_equal(Complex(nan, nan), Complex(nan, nan))
    end
  end

  def test_coerce
    assert_equal([Complex(2),Complex(1)], Complex(1).coerce(2))
    assert_equal([Complex(2.2),Complex(1)], Complex(1).coerce(2.2))
    assert_equal([Complex(Rational(2)),Complex(1)],
		 Complex(1).coerce(Rational(2)))
    assert_equal([Complex(2),Complex(1)], Complex(1).coerce(Complex(2)))

    obj = eval("class C\u{1f5ff}; self; end").new
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) { Complex(1).coerce(obj) }
  end

  class ObjectX
    def +(x) Rational(1) end
    alias - +
    alias * +
    alias / +
    alias quo +
    alias ** +
    def coerce(x) [x, Complex(1)] end
  end

  def test_coerce2
    x = ObjectX.new
    %w(+ - * / quo **).each do |op|
      assert_kind_of(Numeric, Complex(1).__send__(op, x))
    end
  end

  def test_math
    c = Complex(1,2)

    assert_in_delta(2.236, c.abs, 0.001)
    assert_in_delta(2.236, c.magnitude, 0.001)
    assert_equal(5, c.abs2)

    assert_equal(c.abs, Math.sqrt(c * c.conj))
    assert_equal(c.abs, Math.sqrt(c.real**2 + c.imag**2))
    assert_equal(c.abs2, c * c.conj)
    assert_equal(c.abs2, c.real**2 + c.imag**2)

    assert_in_delta(1.107, c.arg, 0.001)
    assert_in_delta(1.107, c.angle, 0.001)
    assert_in_delta(1.107, c.phase, 0.001)

    r = c.polar
    assert_in_delta(2.236, r[0], 0.001)
    assert_in_delta(1.107, r[1], 0.001)
    assert_equal(Complex(1,-2), c.conjugate)
    assert_equal(Complex(1,-2), c.conj)

    assert_equal(Complex(1,2), c.numerator)
    assert_equal(1, c.denominator)
  end

  def test_to_s
    c = Complex(1,2)

    assert_instance_of(String, c.to_s)
    assert_equal('1+2i', c.to_s)

    assert_equal('0+2i', Complex(0,2).to_s)
    assert_equal('0-2i', Complex(0,-2).to_s)
    assert_equal('1+2i', Complex(1,2).to_s)
    assert_equal('-1+2i', Complex(-1,2).to_s)
    assert_equal('-1-2i', Complex(-1,-2).to_s)
    assert_equal('1-2i', Complex(1,-2).to_s)
    assert_equal('-1-2i', Complex(-1,-2).to_s)

    assert_equal('0+2.0i', Complex(0,2.0).to_s)
    assert_equal('0-2.0i', Complex(0,-2.0).to_s)
    assert_equal('1.0+2.0i', Complex(1.0,2.0).to_s)
    assert_equal('-1.0+2.0i', Complex(-1.0,2.0).to_s)
    assert_equal('-1.0-2.0i', Complex(-1.0,-2.0).to_s)
    assert_equal('1.0-2.0i', Complex(1.0,-2.0).to_s)
    assert_equal('-1.0-2.0i', Complex(-1.0,-2.0).to_s)

    assert_equal('0+2/1i', Complex(0,Rational(2)).to_s)
    assert_equal('0-2/1i', Complex(0,Rational(-2)).to_s)
    assert_equal('1+2/1i', Complex(1,Rational(2)).to_s)
    assert_equal('-1+2/1i', Complex(-1,Rational(2)).to_s)
    assert_equal('-1-2/1i', Complex(-1,Rational(-2)).to_s)
    assert_equal('1-2/1i', Complex(1,Rational(-2)).to_s)
    assert_equal('-1-2/1i', Complex(-1,Rational(-2)).to_s)

    assert_equal('0+2/3i', Complex(0,Rational(2,3)).to_s)
    assert_equal('0-2/3i', Complex(0,Rational(-2,3)).to_s)
    assert_equal('1+2/3i', Complex(1,Rational(2,3)).to_s)
    assert_equal('-1+2/3i', Complex(-1,Rational(2,3)).to_s)
    assert_equal('-1-2/3i', Complex(-1,Rational(-2,3)).to_s)
    assert_equal('1-2/3i', Complex(1,Rational(-2,3)).to_s)
    assert_equal('-1-2/3i', Complex(-1,Rational(-2,3)).to_s)

    nan = 0.0 / 0
    inf = 1.0 / 0
    if nan.nan?
      assert_equal('NaN+NaN*i', Complex(nan,nan).to_s)
    end
    if inf.infinite?
      assert_equal('Infinity+Infinity*i', Complex(inf,inf).to_s)
      assert_equal('Infinity-Infinity*i', Complex(inf,-inf).to_s)
    end
  end

  def test_inspect
    c = Complex(1,2)

    assert_instance_of(String, c.inspect)
    assert_equal('(1+2i)', c.inspect)
  end

  def test_marshal
    c = Complex(1,2)

    s = Marshal.dump(c)
    c2 = Marshal.load(s)
    assert_equal(c, c2)
    assert_instance_of(Complex, c2)

    c = Complex(Rational(1,2),Rational(2,3))

    s = Marshal.dump(c)
    c2 = Marshal.load(s)
    assert_equal(c, c2)
    assert_instance_of(Complex, c2)

    bug3656 = '[ruby-core:31622]'
    c = Complex(1,2)
    assert_predicate(c, :frozen?)
    result = c.marshal_load([2,3]) rescue :fail
    assert_equal(:fail, result, bug3656)
    assert_equal(Complex(1,2), c)
  end

  def test_marshal_compatibility
    bug6625 = '[ruby-core:45775]'
    dump = "\x04\x08o:\x0cComplex\x07:\x0a@reali\x06:\x0b@imagei\x07"
    assert_nothing_raised(bug6625) do
      assert_equal(Complex(1, 2), Marshal.load(dump), bug6625)
    end
  end

  def test_parse
    assert_equal(Complex(5), '5'.to_c)
    assert_equal(Complex(-5), '-5'.to_c)
    assert_equal(Complex(5,3), '5+3i'.to_c)
    assert_equal(Complex(-5,3), '-5+3i'.to_c)
    assert_equal(Complex(5,-3), '5-3i'.to_c)
    assert_equal(Complex(-5,-3), '-5-3i'.to_c)
    assert_equal(Complex(0,3), '3i'.to_c)
    assert_equal(Complex(0,-3), '-3i'.to_c)
    assert_equal(Complex(5,1), '5+i'.to_c)
    assert_equal(Complex(0,1), 'i'.to_c)
    assert_equal(Complex(0,1), '+i'.to_c)
    assert_equal(Complex(0,-1), '-i'.to_c)

    assert_equal(Complex(5,3), '5+3I'.to_c)
    assert_equal(Complex(5,3), '5+3j'.to_c)
    assert_equal(Complex(5,3), '5+3J'.to_c)
    assert_equal(Complex(0,3), '3I'.to_c)
    assert_equal(Complex(0,3), '3j'.to_c)
    assert_equal(Complex(0,3), '3J'.to_c)
    assert_equal(Complex(0,1), 'I'.to_c)
    assert_equal(Complex(0,1), 'J'.to_c)

    assert_equal(Complex(5.0), '5.0'.to_c)
    assert_equal(Complex(-5.0), '-5.0'.to_c)
    assert_equal(Complex(5.0,3.0), '5.0+3.0i'.to_c)
    assert_equal(Complex(-5.0,3.0), '-5.0+3.0i'.to_c)
    assert_equal(Complex(5.0,-3.0), '5.0-3.0i'.to_c)
    assert_equal(Complex(-5.0,-3.0), '-5.0-3.0i'.to_c)
    assert_equal(Complex(0.0,3.0), '3.0i'.to_c)
    assert_equal(Complex(0.0,-3.0), '-3.0i'.to_c)

    assert_equal(Complex(5.1), '5.1'.to_c)
    assert_equal(Complex(-5.2), '-5.2'.to_c)
    assert_equal(Complex(5.3,3.4), '5.3+3.4i'.to_c)
    assert_equal(Complex(-5.5,3.6), '-5.5+3.6i'.to_c)
    assert_equal(Complex(5.3,-3.4), '5.3-3.4i'.to_c)
    assert_equal(Complex(-5.5,-3.6), '-5.5-3.6i'.to_c)
    assert_equal(Complex(0.0,3.1), '3.1i'.to_c)
    assert_equal(Complex(0.0,-3.2), '-3.2i'.to_c)

    assert_equal(Complex(5.0), '5e0'.to_c)
    assert_equal(Complex(-5.0), '-5e0'.to_c)
    assert_equal(Complex(5.0,3.0), '5e0+3e0i'.to_c)
    assert_equal(Complex(-5.0,3.0), '-5e0+3e0i'.to_c)
    assert_equal(Complex(5.0,-3.0), '5e0-3e0i'.to_c)
    assert_equal(Complex(-5.0,-3.0), '-5e0-3e0i'.to_c)
    assert_equal(Complex(0.0,3.0), '3e0i'.to_c)
    assert_equal(Complex(0.0,-3.0), '-3e0i'.to_c)

    assert_equal(Complex(5e1), '5e1'.to_c)
    assert_equal(Complex(-5e2), '-5e2'.to_c)
    assert_equal(Complex(5e3,3e4), '5e003+3e4i'.to_c)
    assert_equal(Complex(-5e5,3e6), '-5e5+3e006i'.to_c)
    assert_equal(Complex(5e3,-3e4), '5e003-3e4i'.to_c)
    assert_equal(Complex(-5e5,-3e6), '-5e5-3e006i'.to_c)
    assert_equal(Complex(0.0,3e1), '3e1i'.to_c)
    assert_equal(Complex(0.0,-3e2), '-3e2i'.to_c)

    assert_equal(Complex(0.33), '.33'.to_c)
    assert_equal(Complex(0.33), '0.33'.to_c)
    assert_equal(Complex(-0.33), '-.33'.to_c)
    assert_equal(Complex(-0.33), '-0.33'.to_c)
    assert_equal(Complex(-0.33), '-0.3_3'.to_c)

    assert_equal(Complex.polar(10,10), '10@10'.to_c)
    assert_equal(Complex.polar(-10,-10), '-10@-10'.to_c)
    assert_equal(Complex.polar(10.5,10.5), '10.5@10.5'.to_c)
    assert_equal(Complex.polar(-10.5,-10.5), '-10.5@-10.5'.to_c)

    assert_equal(Complex(5), Complex('5'))
    assert_equal(Complex(-5), Complex('-5'))
    assert_equal(Complex(5,3), Complex('5+3i'))
    assert_equal(Complex(-5,3), Complex('-5+3i'))
    assert_equal(Complex(5,-3), Complex('5-3i'))
    assert_equal(Complex(-5,-3), Complex('-5-3i'))
    assert_equal(Complex(0,3), Complex('3i'))
    assert_equal(Complex(0,-3), Complex('-3i'))
    assert_equal(Complex(5,1), Complex('5+i'))
    assert_equal(Complex(0,1), Complex('i'))
    assert_equal(Complex(0,1), Complex('+i'))
    assert_equal(Complex(0,-1), Complex('-i'))

    assert_equal(Complex(5,3), Complex('5+3I'))
    assert_equal(Complex(5,3), Complex('5+3j'))
    assert_equal(Complex(5,3), Complex('5+3J'))
    assert_equal(Complex(0,3), Complex('3I'))
    assert_equal(Complex(0,3), Complex('3j'))
    assert_equal(Complex(0,3), Complex('3J'))
    assert_equal(Complex(0,1), Complex('I'))
    assert_equal(Complex(0,1), Complex('J'))

    assert_equal(Complex(5.0), Complex('5.0'))
    assert_equal(Complex(-5.0), Complex('-5.0'))
    assert_equal(Complex(5.0,3.0), Complex('5.0+3.0i'))
    assert_equal(Complex(-5.0,3.0), Complex('-5.0+3.0i'))
    assert_equal(Complex(5.0,-3.0), Complex('5.0-3.0i'))
    assert_equal(Complex(-5.0,-3.0), Complex('-5.0-3.0i'))
    assert_equal(Complex(0.0,3.0), Complex('3.0i'))
    assert_equal(Complex(0.0,-3.0), Complex('-3.0i'))

    assert_equal(Complex(5.1), Complex('5.1'))
    assert_equal(Complex(-5.2), Complex('-5.2'))
    assert_equal(Complex(5.3,3.4), Complex('5.3+3.4i'))
    assert_equal(Complex(-5.5,3.6), Complex('-5.5+3.6i'))
    assert_equal(Complex(5.3,-3.4), Complex('5.3-3.4i'))
    assert_equal(Complex(-5.5,-3.6), Complex('-5.5-3.6i'))
    assert_equal(Complex(0.0,3.1), Complex('3.1i'))
    assert_equal(Complex(0.0,-3.2), Complex('-3.2i'))

    assert_equal(Complex(5.0), Complex('5e0'))
    assert_equal(Complex(-5.0), Complex('-5e0'))
    assert_equal(Complex(5.0,3.0), Complex('5e0+3e0i'))
    assert_equal(Complex(-5.0,3.0), Complex('-5e0+3e0i'))
    assert_equal(Complex(5.0,-3.0), Complex('5e0-3e0i'))
    assert_equal(Complex(-5.0,-3.0), Complex('-5e0-3e0i'))
    assert_equal(Complex(0.0,3.0), Complex('3e0i'))
    assert_equal(Complex(0.0,-3.0), Complex('-3e0i'))

    assert_equal(Complex(5e1), Complex('5e1'))
    assert_equal(Complex(-5e2), Complex('-5e2'))
    assert_equal(Complex(5e3,3e4), Complex('5e003+3e4i'))
    assert_equal(Complex(-5e5,3e6), Complex('-5e5+3e006i'))
    assert_equal(Complex(5e3,-3e4), Complex('5e003-3e4i'))
    assert_equal(Complex(-5e5,-3e6), Complex('-5e5-3e006i'))
    assert_equal(Complex(0.0,3e1), Complex('3e1i'))
    assert_equal(Complex(0.0,-3e2), Complex('-3e2i'))

    assert_equal(Complex(0.33), Complex('.33'))
    assert_equal(Complex(0.33), Complex('0.33'))
    assert_equal(Complex(-0.33), Complex('-.33'))
    assert_equal(Complex(-0.33), Complex('-0.33'))
    assert_equal(Complex(-0.33), Complex('-0.3_3'))

    assert_equal(Complex.polar(10,10), Complex('10@10'))
    assert_equal(Complex.polar(-10,-10), Complex('-10@-10'))
    assert_equal(Complex.polar(10.5,10.5), Complex('10.5@10.5'))
    assert_equal(Complex.polar(-10.5,-10.5), Complex('-10.5@-10.5'))

    assert_equal(Complex(0), ''.to_c)
    assert_equal(Complex(0), ' '.to_c)
    assert_equal(Complex(5), "\f\n\r\t\v5\0".to_c)
    assert_equal(Complex(0), '_'.to_c)
    assert_equal(Complex(0), '_5'.to_c)
    assert_equal(Complex(5), '5_'.to_c)
    assert_equal(Complex(5), '5x'.to_c)
    assert_equal(Complex(5), '5+_3i'.to_c)
    assert_equal(Complex(5), '5+3_i'.to_c)
    assert_equal(Complex(5,3), '5+3i_'.to_c)
    assert_equal(Complex(5,3), '5+3ix'.to_c)
    assert_raise(ArgumentError){ Complex('')}
    assert_raise(ArgumentError){ Complex('_')}
    assert_raise(ArgumentError){ Complex("\f\n\r\t\v5\0")}
    assert_raise(ArgumentError){ Complex('_5')}
    assert_raise(ArgumentError){ Complex('5_')}
    assert_raise(ArgumentError){ Complex('5x')}
    assert_raise(ArgumentError){ Complex('5+_3i')}
    assert_raise(ArgumentError){ Complex('5+3_i')}
    assert_raise(ArgumentError){ Complex('5+3i_')}
    assert_raise(ArgumentError){ Complex('5+3ix')}

    assert_equal(Complex(Rational(1,5)), '1/5'.to_c)
    assert_equal(Complex(Rational(-1,5)), '-1/5'.to_c)
    assert_equal(Complex(Rational(1,5),3), '1/5+3i'.to_c)
    assert_equal(Complex(Rational(1,5),-3), '1/5-3i'.to_c)
    assert_equal(Complex(Rational(-1,5),3), '-1/5+3i'.to_c)
    assert_equal(Complex(Rational(-1,5),-3), '-1/5-3i'.to_c)
    assert_equal(Complex(Rational(1,5),Rational(3,2)), '1/5+3/2i'.to_c)
    assert_equal(Complex(Rational(1,5),Rational(-3,2)), '1/5-3/2i'.to_c)
    assert_equal(Complex(Rational(-1,5),Rational(3,2)), '-1/5+3/2i'.to_c)
    assert_equal(Complex(Rational(-1,5),Rational(-3,2)), '-1/5-3/2i'.to_c)
    assert_equal(Complex(Rational(1,5),Rational(3,2)), '1/5+3/2i'.to_c)
    assert_equal(Complex(Rational(1,5),Rational(-3,2)), '1/5-3/2i'.to_c)
    assert_equal(Complex(Rational(-1,5),Rational(3,2)), '-1/5+3/2i'.to_c)
    assert_equal(Complex(Rational(-1,5),Rational(-3,2)), '-1/5-3/2i'.to_c)
    assert_equal(Complex.polar(Rational(1,5),Rational(3,2)), Complex('1/5@3/2'))
    assert_equal(Complex.polar(Rational(-1,5),Rational(-3,2)), Complex('-1/5@-3/2'))

  end

  def test_respond
    c = Complex(1,1)
    assert_not_respond_to(c, :%)
    assert_not_respond_to(c, :<=>)
    assert_not_respond_to(c, :div)
    assert_not_respond_to(c, :divmod)
    assert_not_respond_to(c, :floor)
    assert_not_respond_to(c, :ceil)
    assert_not_respond_to(c, :modulo)
    assert_not_respond_to(c, :remainder)
    assert_not_respond_to(c, :round)
    assert_not_respond_to(c, :step)
    assert_not_respond_to(c, :tunrcate)

    assert_not_respond_to(c, :positive?)
    assert_not_respond_to(c, :negative?)
    assert_not_respond_to(c, :sign)

    assert_not_respond_to(c, :quotient)
    assert_not_respond_to(c, :quot)
    assert_not_respond_to(c, :quotrem)

    assert_not_respond_to(c, :gcd)
    assert_not_respond_to(c, :lcm)
    assert_not_respond_to(c, :gcdlcm)

    (Comparable.instance_methods(false) - Complex.instance_methods(false)).each do |n|
      assert_not_respond_to(c, n, "Complex##{n}")
    end
  end

  def test_to_i
    assert_equal(3, Complex(3).to_i)
    assert_equal(3, Integer(Complex(3)))
    assert_raise(RangeError){Complex(3,2).to_i}
    assert_raise(RangeError){Integer(Complex(3,2))}
  end

  def test_to_f
    assert_equal(3.0, Complex(3).to_f)
    assert_equal(3.0, Float(Complex(3)))
    assert_raise(RangeError){Complex(3,2).to_f}
    assert_raise(RangeError){Float(Complex(3,2))}
  end

  def test_to_r
    assert_equal(Rational(3), Complex(3).to_r)
    assert_equal(Rational(3), Rational(Complex(3)))
    assert_raise(RangeError){Complex(3,2).to_r}
    assert_raise(RangeError){Rational(Complex(3,2))}
  end

  def test_to_c
    c = nil.to_c
    assert_equal([0,0], [c.real, c.imag])

    c = 0.to_c
    assert_equal([0,0], [c.real, c.imag])

    c = 1.to_c
    assert_equal([1,0], [c.real, c.imag])

    c = 1.1.to_c
    assert_equal([1.1, 0], [c.real, c.imag])

    c = Rational(1,2).to_c
    assert_equal([Rational(1,2), 0], [c.real, c.imag])

    c = Complex(1,2).to_c
    assert_equal([1, 2], [c.real, c.imag])

    if (0.0/0).nan?
      assert_nothing_raised{(0.0/0).to_c}
    end
    if (1.0/0).infinite?
      assert_nothing_raised{(1.0/0).to_c}
    end
  end

  def test_finite_p
    assert_predicate(1+1i, :finite?)
    assert_predicate(1-1i, :finite?)
    assert_predicate(-1+1i, :finite?)
    assert_predicate(-1-1i, :finite?)
    assert_not_predicate(Float::INFINITY + 1i, :finite?)
    assert_not_predicate(Complex(1, Float::INFINITY), :finite?)
    assert_predicate(Complex(Float::MAX, 0.0), :finite?)
    assert_predicate(Complex(0.0, Float::MAX), :finite?)
    assert_predicate(Complex(Float::MAX, Float::MAX), :finite?)
    assert_not_predicate(Complex(Float::NAN, 0), :finite?)
    assert_not_predicate(Complex(0, Float::NAN), :finite?)
    assert_not_predicate(Complex(Float::NAN, Float::NAN), :finite?)
  end

  def test_infinite_p
    assert_nil((1+1i).infinite?)
    assert_nil((1-1i).infinite?)
    assert_nil((-1+1i).infinite?)
    assert_nil((-1-1i).infinite?)
    assert_equal(1, (Float::INFINITY + 1i).infinite?)
    assert_equal(1, (Float::INFINITY - 1i).infinite?)
    assert_equal(1, (-Float::INFINITY + 1i).infinite?)
    assert_equal(1, (-Float::INFINITY - 1i).infinite?)
    assert_equal(1, Complex(1, Float::INFINITY).infinite?)
    assert_equal(1, Complex(-1, Float::INFINITY).infinite?)
    assert_equal(1, Complex(1, -Float::INFINITY).infinite?)
    assert_equal(1, Complex(-1, -Float::INFINITY).infinite?)
    assert_nil(Complex(Float::MAX, 0.0).infinite?)
    assert_nil(Complex(0.0, Float::MAX).infinite?)
    assert_nil(Complex(Float::MAX, Float::MAX).infinite?)
    assert_nil(Complex(Float::NAN, 0).infinite?)
    assert_nil(Complex(0, Float::NAN).infinite?)
    assert_nil(Complex(Float::NAN, Float::NAN).infinite?)
  end

  def test_supp
    assert_predicate(1, :real?)
    assert_predicate(1.1, :real?)

    assert_equal(1, 1.real)
    assert_equal(0, 1.imag)
    assert_equal(0, 1.imaginary)

    assert_equal(1.1, 1.1.real)
    assert_equal(0, 1.1.imag)
    assert_equal(0, 1.1.imaginary)

    assert_equal(1, 1.magnitude)
    assert_equal(1, -1.magnitude)
    assert_equal(1, 1.0.magnitude)
    assert_equal(1, -1.0.magnitude)

    assert_equal(4, 2.abs2)
    assert_equal(4, -2.abs2)
    assert_equal(4.0, 2.0.abs2)
    assert_equal(4.0, -2.0.abs2)

    assert_equal(0, 1.arg)
    assert_equal(0, 1.angle)
    assert_equal(0, 1.phase)

    assert_equal(0, 1.0.arg)
    assert_equal(0, 1.0.angle)
    assert_equal(0, 1.0.phase)

    if (0.0/0).nan?
      nan = 0.0/0
      assert_same(nan, nan.arg)
      assert_same(nan, nan.angle)
      assert_same(nan, nan.phase)
    end

    assert_equal(Math::PI, -1.arg)
    assert_equal(Math::PI, -1.angle)
    assert_equal(Math::PI, -1.phase)

    assert_equal(Math::PI, -1.0.arg)
    assert_equal(Math::PI, -1.0.angle)
    assert_equal(Math::PI, -1.0.phase)

    assert_equal([1,0], 1.rect)
    assert_equal([-1,0], -1.rect)
    assert_equal([1,0], 1.rectangular)
    assert_equal([-1,0], -1.rectangular)

    assert_equal([1.0,0], 1.0.rect)
    assert_equal([-1.0,0], -1.0.rect)
    assert_equal([1.0,0], 1.0.rectangular)
    assert_equal([-1.0,0], -1.0.rectangular)

    assert_equal([1,0], 1.polar)
    assert_equal([1, Math::PI], -1.polar)

    assert_equal([1.0,0], 1.0.polar)
    assert_equal([1.0, Math::PI], -1.0.polar)

    assert_equal(1, 1.conjugate)
    assert_equal(-1, -1.conjugate)
    assert_equal(1, 1.conj)
    assert_equal(-1, -1.conj)

    assert_equal(1.1, 1.1.conjugate)
    assert_equal(-1.1, -1.1.conjugate)
    assert_equal(1.1, 1.1.conj)
    assert_equal(-1.1, -1.1.conj)

    assert_equal(Complex(Rational(1,2),Rational(1)), Complex(1,2).quo(2))

    assert_equal(0.5, 1.fdiv(2))
    assert_equal(5000000000.0, 10000000000.fdiv(2))
    assert_equal(0.5, 1.0.fdiv(2))
    assert_equal(0.25, Rational(1,2).fdiv(2))
    assert_equal(Complex(0.5,1.0), Complex(1,2).quo(2))
  end

  def test_ruby19
    assert_raise(NoMethodError){ Complex.new(1) }
    assert_raise(NoMethodError){ Complex.new!(1) }
    assert_raise(NoMethodError){ Complex.reduce(1) }
  end

  def test_fixed_bug
    assert_equal(Complex(1), 1 ** Complex(1))
    assert_equal('-1.0-0.0i', Complex(-1.0, -0.0).to_s)
    assert_in_delta(Math::PI, Complex(-0.0).arg, 0.001)
    assert_equal(Complex(2e3, 2e4), '2e3+2e4i'.to_c)
    assert_raise(ArgumentError){ Complex('--8i')}
  end

  def test_known_bug
  end

end
