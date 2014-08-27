require 'test/unit'

class RationalSub < Rational; end

class Rational_Test < Test::Unit::TestCase

  def test_ratsub
    c = RationalSub.__send__(:convert, 1)

    assert_kind_of(Numeric, c)

    assert_instance_of(RationalSub, c)

    c2 = c + 1
    assert_instance_of(RationalSub, c2)
    c2 = c - 1
    assert_instance_of(RationalSub, c2)

    c3 = c - c2
    assert_instance_of(RationalSub, c3)

    s = Marshal.dump(c)
    c5 = Marshal.load(s)
    assert_equal(c, c5)
    assert_instance_of(RationalSub, c5)

    c1 = Rational(1)
    assert_equal(c1.hash, c.hash, '[ruby-dev:38850]')
    assert_equal([true, true], [c.eql?(c1), c1.eql?(c)])
  end

  def test_eql_p
    c = Rational(0)
    c2 = Rational(0)
    c3 = Rational(1)

    assert_equal(true, c.eql?(c2))
    assert_equal(false, c.eql?(c3))

    assert_equal(false, c.eql?(0))
  end

  def test_hash
    assert_instance_of(Fixnum, Rational(1,2).hash)

    h = {}
    h[Rational(0)] = 0
    h[Rational(1,1)] = 1
    h[Rational(2,1)] = 2
    h[Rational(3,1)] = 3

    assert_equal(4, h.size)
    assert_equal(2, h[Rational(2,1)])

    h[Rational(0,1)] = 9
    assert_equal(4, h.size)
  end

  def test_freeze
    c = Rational(1)
    c.freeze
    assert_equal(true, c.frozen?)
    assert_instance_of(String, c.to_s)
  end

  def test_conv
    c = Rational(0,1)
    assert_equal(Rational(0,1), c)

    c = Rational(2**32, 2**32)
    assert_equal(Rational(2**32,2**32), c)
    assert_equal([1,1], [c.numerator,c.denominator])

    c = Rational(-2**32, 2**32)
    assert_equal(Rational(-2**32,2**32), c)
    assert_equal([-1,1], [c.numerator,c.denominator])

    c = Rational(2**32, -2**32)
    assert_equal(Rational(2**32,-2**32), c)
    assert_equal([-1,1], [c.numerator,c.denominator])

    c = Rational(-2**32, -2**32)
    assert_equal(Rational(-2**32,-2**32), c)
    assert_equal([1,1], [c.numerator,c.denominator])

    c = Rational(Rational(1,2),2)
    assert_equal(Rational(1,4), c)

    c = Rational(2,Rational(1,2))
    assert_equal(Rational(4), c)

    c = Rational(Rational(1,2),Rational(1,2))
    assert_equal(Rational(1), c)

    c = Rational(Complex(1,2),2)
    assert_equal(Complex(Rational(1,2),1), c)

    c = Rational(2,Complex(1,2))
    assert_equal(Complex(Rational(2,5),Rational(-4,5)), c)

    c = Rational(Complex(1,2),Complex(1,2))
    assert_equal(Rational(1), c)

    assert_equal(Rational(3),Rational(3))
    assert_equal(Rational(1),Rational(3,3))
    assert_equal(3.3.to_r,Rational(3.3))
    assert_equal(1,Rational(3.3,3.3))
    assert_equal(Rational(3),Rational('3'))
    assert_equal(Rational(1),Rational('3.0','3.0'))
    assert_equal(Rational(1),Rational('3/3','3/3'))
    assert_raise(TypeError){Rational(nil)}
    assert_raise(ArgumentError){Rational('')}
    assert_raise(TypeError){Rational(Object.new)}
    assert_raise(ArgumentError){Rational()}
    assert_raise(ArgumentError){Rational(1,2,3)}

    if (0.0/0).nan?
      assert_raise(FloatDomainError){Rational(0.0/0)}
    end
    if (1.0/0).infinite?
      assert_raise(FloatDomainError){Rational(1.0/0)}
    end
  end

  def test_attr
    c = Rational(4)

    assert_equal(4, c.numerator)
    assert_equal(1, c.denominator)

    c = Rational(4,5)

    assert_equal(4, c.numerator)
    assert_equal(5, c.denominator)

    c = Rational(4)

    assert_equal(4, c.numerator)
    assert_equal(1, c.denominator)

    c = Rational(4,5)

    assert_equal(4, c.numerator)
    assert_equal(5, c.denominator)

    c = Rational(4)

    assert_equal(4, c.numerator)
    assert_equal(1, c.denominator)

    c = Rational(4,5)

    assert_equal(4, c.numerator)
    assert_equal(5, c.denominator)
  end

  def test_attr2
    c = Rational(1)

    assert_equal(false, c.integer?)
    assert_equal(true, c.real?)

    assert_equal(true, Rational(0).zero?)
    assert_equal(true, Rational(0,1).zero?)
    assert_equal(false, Rational(1,1).zero?)

    assert_equal(nil, Rational(0).nonzero?)
    assert_equal(nil, Rational(0,1).nonzero?)
    assert_equal(Rational(1,1), Rational(1,1).nonzero?)
  end

  def test_uplus
    assert_equal(Rational(1), +Rational(1))
    assert_equal(Rational(-1), +Rational(-1))
    assert_equal(Rational(1,1), +Rational(1,1))
    assert_equal(Rational(-1,1), +Rational(-1,1))
    assert_equal(Rational(-1,1), +Rational(1,-1))
    assert_equal(Rational(1,1), +Rational(-1,-1))
  end

  def test_negate
    assert_equal(Rational(-1), -Rational(1))
    assert_equal(Rational(1), -Rational(-1))
    assert_equal(Rational(-1,1), -Rational(1,1))
    assert_equal(Rational(1,1), -Rational(-1,1))
    assert_equal(Rational(1,1), -Rational(1,-1))
    assert_equal(Rational(-1,1), -Rational(-1,-1))
  end

  def test_add
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_equal(Rational(7,6), c + c2)

    assert_equal(Rational(5,2), c + 2)
    assert_equal(2.5, c + 2.0)
  end

  def test_sub
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_equal(Rational(-1,6), c - c2)

    assert_equal(Rational(-3,2), c - 2)
    assert_equal(-1.5, c - 2.0)
  end

  def test_mul
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_equal(Rational(1,3), c * c2)

    assert_equal(Rational(1,1), c * 2)
    assert_equal(1.0, c * 2.0)
  end

  def test_div
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_equal(Rational(3,4), c / c2)

    assert_equal(Rational(1,4), c / 2)
    assert_equal(0.25, c / 2.0)

    assert_raise(ZeroDivisionError){Rational(1, 3) / 0}
    assert_raise(ZeroDivisionError){Rational(1, 3) / Rational(0)}

    assert_equal(0, Rational(1, 3) / Float::INFINITY)
    assert_predicate(Rational(1, 3) / 0.0, :infinite?, '[ruby-core:31626]')
  end

  def assert_eql(exp, act, *args)
    unless Array === exp
      exp = [exp]
    end
    unless Array === act
      act = [act]
    end
    exp.zip(act).each do |e, a|
      na = [e, a] + args
      assert_equal(*na)
      na = [e.class, a] + args
      assert_instance_of(*na)
    end
  end

  def test_idiv
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_eql(0, c.div(c2))
    assert_eql(0, c.div(2))
    assert_eql(0, c.div(2.0))

    c = Rational(301,100)
    c2 = Rational(7,5)

    assert_equal(2, c.div(c2))
    assert_equal(-3, c.div(-c2))
    assert_equal(-3, (-c).div(c2))
    assert_equal(2, (-c).div(-c2))

    c = Rational(301,100)
    c2 = Rational(2)

    assert_equal(1, c.div(c2))
    assert_equal(-2, c.div(-c2))
    assert_equal(-2, (-c).div(c2))
    assert_equal(1, (-c).div(-c2))

    c = Rational(11)
    c2 = Rational(3)

    assert_equal(3, c.div(c2))
    assert_equal(-4, c.div(-c2))
    assert_equal(-4, (-c).div(c2))
    assert_equal(3, (-c).div(-c2))
  end

  def test_modulo
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_eql(Rational(1,2), c.modulo(c2))
    assert_eql(Rational(1,2), c.modulo(2))
    assert_eql(0.5, c.modulo(2.0))

    c = Rational(301,100)
    c2 = Rational(7,5)

    assert_equal(Rational(21,100), c.modulo(c2))
    assert_equal(Rational(-119,100), c.modulo(-c2))
    assert_equal(Rational(119,100), (-c).modulo(c2))
    assert_equal(Rational(-21,100), (-c).modulo(-c2))

    c = Rational(301,100)
    c2 = Rational(2)

    assert_equal(Rational(101,100), c.modulo(c2))
    assert_equal(Rational(-99,100), c.modulo(-c2))
    assert_equal(Rational(99,100), (-c).modulo(c2))
    assert_equal(Rational(-101,100), (-c).modulo(-c2))

    c = Rational(11)
    c2 = Rational(3)

    assert_equal(2, c.modulo(c2))
    assert_equal(-1, c.modulo(-c2))
    assert_equal(1, (-c).modulo(c2))
    assert_equal(-2, (-c).modulo(-c2))
  end

  def test_divmod
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_eql([0, Rational(1,2)], c.divmod(c2))
    assert_eql([0, Rational(1,2)], c.divmod(2))
    assert_eql([0, 0.5], c.divmod(2.0))

    c = Rational(301,100)
    c2 = Rational(7,5)

    assert_equal([2, Rational(21,100)], c.divmod(c2))
    assert_equal([-3, Rational(-119,100)], c.divmod(-c2))
    assert_equal([-3, Rational(119,100)], (-c).divmod(c2))
    assert_equal([2, Rational(-21,100)], (-c).divmod(-c2))

    c = Rational(301,100)
    c2 = Rational(2)

    assert_equal([1, Rational(101,100)], c.divmod(c2))
    assert_equal([-2, Rational(-99,100)], c.divmod(-c2))
    assert_equal([-2, Rational(99,100)], (-c).divmod(c2))
    assert_equal([1, Rational(-101,100)], (-c).divmod(-c2))

    c = Rational(11)
    c2 = Rational(3)

    assert_equal([3,2], c.divmod(c2))
    assert_equal([-4,-1], c.divmod(-c2))
    assert_equal([-4,1], (-c).divmod(c2))
    assert_equal([3,-2], (-c).divmod(-c2))
  end

  def test_remainder
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_eql(Rational(1,2), c.remainder(c2))
    assert_eql(Rational(1,2), c.remainder(2))
    assert_eql(0.5, c.remainder(2.0))

    c = Rational(301,100)
    c2 = Rational(7,5)

    assert_equal(Rational(21,100), c.remainder(c2))
    assert_equal(Rational(21,100), c.remainder(-c2))
    assert_equal(Rational(-21,100), (-c).remainder(c2))
    assert_equal(Rational(-21,100), (-c).remainder(-c2))

    c = Rational(301,100)
    c2 = Rational(2)

    assert_equal(Rational(101,100), c.remainder(c2))
    assert_equal(Rational(101,100), c.remainder(-c2))
    assert_equal(Rational(-101,100), (-c).remainder(c2))
    assert_equal(Rational(-101,100), (-c).remainder(-c2))

    c = Rational(11)
    c2 = Rational(3)

    assert_equal(2, c.remainder(c2))
    assert_equal(2, c.remainder(-c2))
    assert_equal(-2, (-c).remainder(c2))
    assert_equal(-2, (-c).remainder(-c2))
  end

  def test_quo
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_equal(Rational(3,4), c.quo(c2))

    assert_equal(Rational(1,4), c.quo(2))
    assert_equal(0.25, c.quo(2.0))
  end

  def test_fdiv
    c = Rational(1,2)
    c2 = Rational(2,3)

    assert_equal(0.75, c.fdiv(c2))

    assert_equal(0.25, c.fdiv(2))
    assert_equal(0.25, c.fdiv(2.0))
    assert_equal(0, c.fdiv(Float::INFINITY))
    assert_predicate(c.fdiv(0), :infinite?, '[ruby-core:31626]')
  end

  def test_expt
    c = Rational(1,2)
    c2 = Rational(2,3)

    r = c ** c2
    assert_in_delta(0.6299, r, 0.001)

    assert_equal(Rational(1,4), c ** 2)
    assert_equal(Rational(4), c ** -2)
    assert_equal(Rational(1,4), (-c) ** 2)
    assert_equal(Rational(4), (-c) ** -2)

    assert_equal(0.25, c ** 2.0)
    assert_equal(4.0, c ** -2.0)

    assert_equal(Rational(1,4), c ** Rational(2))
    assert_equal(Rational(4), c ** Rational(-2))

    assert_equal(Rational(1), 0 ** Rational(0))
    assert_equal(Rational(1), Rational(0) ** 0)
    assert_equal(Rational(1), Rational(0) ** Rational(0))

    # p ** p
    x = 2 ** Rational(2)
    assert_equal(Rational(4), x)
    assert_instance_of(Rational, x)
    assert_equal(4, x.numerator)
    assert_equal(1, x.denominator)

    x = Rational(2) ** 2
    assert_equal(Rational(4), x)
    assert_instance_of(Rational, x)
    assert_equal(4, x.numerator)
    assert_equal(1, x.denominator)

    x = Rational(2) ** Rational(2)
    assert_equal(Rational(4), x)
    assert_instance_of(Rational, x)
    assert_equal(4, x.numerator)
    assert_equal(1, x.denominator)

    # -p ** p
    x = (-2) ** Rational(2)
    assert_equal(Rational(4), x)
    assert_instance_of(Rational, x)
    assert_equal(4, x.numerator)
    assert_equal(1, x.denominator)

    x = Rational(-2) ** 2
    assert_equal(Rational(4), x)
    assert_instance_of(Rational, x)
    assert_equal(4, x.numerator)
    assert_equal(1, x.denominator)

    x = Rational(-2) ** Rational(2)
    assert_equal(Rational(4), x)
    assert_instance_of(Rational, x)
    assert_equal(4, x.numerator)
    assert_equal(1, x.denominator)

    # p ** -p
    x = 2 ** Rational(-2)
    assert_equal(Rational(1,4), x)
    assert_instance_of(Rational, x)
    assert_equal(1, x.numerator)
    assert_equal(4, x.denominator)

    x = Rational(2) ** -2
    assert_equal(Rational(1,4), x)
    assert_instance_of(Rational, x)
    assert_equal(1, x.numerator)
    assert_equal(4, x.denominator)

    x = Rational(2) ** Rational(-2)
    assert_equal(Rational(1,4), x)
    assert_instance_of(Rational, x)
    assert_equal(1, x.numerator)
    assert_equal(4, x.denominator)

    # -p ** -p
    x = (-2) ** Rational(-2)
    assert_equal(Rational(1,4), x)
    assert_instance_of(Rational, x)
    assert_equal(1, x.numerator)
    assert_equal(4, x.denominator)

    x = Rational(-2) ** -2
    assert_equal(Rational(1,4), x)
    assert_instance_of(Rational, x)
    assert_equal(1, x.numerator)
    assert_equal(4, x.denominator)

    x = Rational(-2) ** Rational(-2)
    assert_equal(Rational(1,4), x)
    assert_instance_of(Rational, x)
    assert_equal(1, x.numerator)
    assert_equal(4, x.denominator)

    assert_raise(ZeroDivisionError){0 ** -1}
  end

  def test_cmp
    assert_equal(-1, Rational(-1) <=> Rational(0))
    assert_equal(0, Rational(0) <=> Rational(0))
    assert_equal(+1, Rational(+1) <=> Rational(0))

    assert_equal(-1, Rational(-1) <=> 0)
    assert_equal(0, Rational(0) <=> 0)
    assert_equal(+1, Rational(+1) <=> 0)

    assert_equal(-1, Rational(-1) <=> 0.0)
    assert_equal(0, Rational(0) <=> 0.0)
    assert_equal(+1, Rational(+1) <=> 0.0)

    assert_equal(-1, Rational(1,2) <=> Rational(2,3))
    assert_equal(0, Rational(2,3) <=> Rational(2,3))
    assert_equal(+1, Rational(2,3) <=> Rational(1,2))

    f = 2**30-1
    b = 2**30

    assert_equal(0, Rational(f) <=> Rational(f))
    assert_equal(-1, Rational(f) <=> Rational(b))
    assert_equal(+1, Rational(b) <=> Rational(f))
    assert_equal(0, Rational(b) <=> Rational(b))

    assert_equal(-1, Rational(f-1) <=> Rational(f))
    assert_equal(+1, Rational(f) <=> Rational(f-1))
    assert_equal(-1, Rational(b-1) <=> Rational(b))
    assert_equal(+1, Rational(b) <=> Rational(b-1))

    assert_equal(false, Rational(0) < Rational(0))
    assert_equal(true, Rational(0) <= Rational(0))
    assert_equal(true, Rational(0) >= Rational(0))
    assert_equal(false, Rational(0) > Rational(0))

    assert_equal(nil, Rational(0) <=> nil)
    assert_equal(nil, Rational(0) <=> 'foo')
  end

  def test_eqeq
    assert_equal(Rational(1,1), Rational(1))
    assert_equal(Rational(-1,1), Rational(-1))

    assert_equal(false, Rational(2,1) == Rational(1))
    assert_equal(true, Rational(2,1) != Rational(1))
    assert_equal(false, Rational(1) == nil)
    assert_equal(false, Rational(1) == '')
  end

  def test_coerce
    assert_equal([Rational(2),Rational(1)], Rational(1).coerce(2))
    assert_equal([Rational(2.2),Rational(1)], Rational(1).coerce(2.2))
    assert_equal([Rational(2),Rational(1)], Rational(1).coerce(Rational(2)))

    assert_nothing_raised(TypeError, '[Bug #5020] [ruby-devl:44088]') do
      Rational(1,2).coerce(Complex(1,1))
    end
  end

  class ObjectX
    def + (x) Rational(1) end
    alias - +
    alias * +
    alias / +
    alias quo +
    alias div +
    alias % +
    alias remainder +
    alias ** +
    def coerce(x) [x, Rational(1)] end
  end

  def test_coerce2
    x = ObjectX.new
    %w(+ - * / quo div % remainder **).each do |op|
      assert_kind_of(Numeric, Rational(1).__send__(op, x))
    end
  end

  def test_math
    assert_equal(Rational(1,2), Rational(1,2).abs)
    assert_equal(Rational(1,2), Rational(-1,2).abs)
    assert_equal(Rational(1,2), Rational(1,2).magnitude)
    assert_equal(Rational(1,2), Rational(-1,2).magnitude)

    assert_equal(1, Rational(1,2).numerator)
    assert_equal(2, Rational(1,2).denominator)
  end

  def test_trunc
    [[Rational(13, 5),  [ 2,  3,  2,  3]], #  2.6
     [Rational(5, 2),   [ 2,  3,  2,  3]], #  2.5
     [Rational(12, 5),  [ 2,  3,  2,  2]], #  2.4
     [Rational(-12,5),  [-3, -2, -2, -2]], # -2.4
     [Rational(-5, 2),  [-3, -2, -2, -3]], # -2.5
     [Rational(-13, 5), [-3, -2, -2, -3]], # -2.6
    ].each do |i, a|
      assert_equal(a[0], i.floor)
      assert_equal(a[1], i.ceil)
      assert_equal(a[2], i.truncate)
      assert_equal(a[3], i.round)
    end
  end

  def test_to_s
    c = Rational(1,2)

    assert_instance_of(String, c.to_s)
    assert_equal('1/2', c.to_s)

    assert_equal('0/1', Rational(0,2).to_s)
    assert_equal('0/1', Rational(0,-2).to_s)
    assert_equal('1/2', Rational(1,2).to_s)
    assert_equal('-1/2', Rational(-1,2).to_s)
    assert_equal('1/2', Rational(-1,-2).to_s)
    assert_equal('-1/2', Rational(1,-2).to_s)
    assert_equal('1/2', Rational(-1,-2).to_s)
  end

  def test_inspect
    c = Rational(1,2)

    assert_instance_of(String, c.inspect)
    assert_equal('(1/2)', c.inspect)
  end

  def test_marshal
    c = Rational(1,2)
    c.instance_eval{@ivar = 9}

    s = Marshal.dump(c)
    c2 = Marshal.load(s)
    assert_equal(c, c2)
    assert_equal(9, c2.instance_variable_get(:@ivar))
    assert_instance_of(Rational, c2)

    assert_raise(ZeroDivisionError){
      Marshal.load("\x04\bU:\rRational[\ai\x06i\x05")
    }

    bug3656 = '[ruby-core:31622]'
    c = Rational(1,2)
    c.freeze
    assert_predicate(c, :frozen?)
    result = c.marshal_load([2,3]) rescue :fail
    assert_equal(:fail, result, bug3656)
  end

  def test_marshal_compatibility
    bug6625 = '[ruby-core:45775]'
    dump = "\x04\x08o:\x0dRational\x07:\x11@denominatori\x07:\x0f@numeratori\x06"
    assert_nothing_raised(bug6625) do
      assert_equal(Rational(1, 2), Marshal.load(dump), bug6625)
    end
  end

  def test_parse
    assert_equal(Rational(5), '5'.to_r)
    assert_equal(Rational(-5), '-5'.to_r)
    assert_equal(Rational(5,3), '5/3'.to_r)
    assert_equal(Rational(-5,3), '-5/3'.to_r)

    assert_equal(Rational(5), '5.0'.to_r)
    assert_equal(Rational(-5), '-5.0'.to_r)
    assert_equal(Rational(5,3), '5.0/3'.to_r)
    assert_equal(Rational(-5,3), '-5.0/3'.to_r)

    assert_equal(Rational(5), '5e0'.to_r)
    assert_equal(Rational(-5), '-5e0'.to_r)
    assert_equal(Rational(5,3), '5e0/3'.to_r)
    assert_equal(Rational(-5,3), '-5e0/3'.to_r)

    assert_equal(Rational(5e1), '5e1'.to_r)
    assert_equal(Rational(-5e2), '-5e2'.to_r)
    assert_equal(Rational(5e3,3), '5e003/3'.to_r)
    assert_equal(Rational(-5e4,3), '-5e004/3'.to_r)

    assert_equal(Rational(33,100), '.33'.to_r)
    assert_equal(Rational(33,100), '0.33'.to_r)
    assert_equal(Rational(-33,100), '-.33'.to_r)
    assert_equal(Rational(-33,100), '-0.33'.to_r)
    assert_equal(Rational(-33,100), '-0.3_3'.to_r)

    assert_equal(Rational(1,2), '5e-1'.to_r)
    assert_equal(Rational(50), '5e+1'.to_r)
    assert_equal(Rational(1,2), '5.0e-1'.to_r)
    assert_equal(Rational(50), '5.0e+1'.to_r)
    assert_equal(Rational(50), '5e1'.to_r)
    assert_equal(Rational(50), '5E1'.to_r)
    assert_equal(Rational(500), '5e2'.to_r)
    assert_equal(Rational(5000), '5e3'.to_r)
    assert_equal(Rational(500000000000), '5e1_1'.to_r)

    assert_equal(Rational(5), Rational('5'))
    assert_equal(Rational(-5), Rational('-5'))
    assert_equal(Rational(5,3), Rational('5/3'))
    assert_equal(Rational(-5,3), Rational('-5/3'))

    assert_equal(Rational(5), Rational('5.0'))
    assert_equal(Rational(-5), Rational('-5.0'))
    assert_equal(Rational(5,3), Rational('5.0/3'))
    assert_equal(Rational(-5,3), Rational('-5.0/3'))

    assert_equal(Rational(5), Rational('5e0'))
    assert_equal(Rational(-5), Rational('-5e0'))
    assert_equal(Rational(5,3), Rational('5e0/3'))
    assert_equal(Rational(-5,3), Rational('-5e0/3'))

    assert_equal(Rational(5e1), Rational('5e1'))
    assert_equal(Rational(-5e2), Rational('-5e2'))
    assert_equal(Rational(5e3,3), Rational('5e003/3'))
    assert_equal(Rational(-5e4,3), Rational('-5e004/3'))

    assert_equal(Rational(33,100), Rational('.33'))
    assert_equal(Rational(33,100), Rational('0.33'))
    assert_equal(Rational(-33,100), Rational('-.33'))
    assert_equal(Rational(-33,100), Rational('-0.33'))
    assert_equal(Rational(-33,100), Rational('-0.3_3'))

    assert_equal(Rational(1,2), Rational('5e-1'))
    assert_equal(Rational(50), Rational('5e+1'))
    assert_equal(Rational(1,2), Rational('5.0e-1'))
    assert_equal(Rational(50), Rational('5.0e+1'))
    assert_equal(Rational(50), Rational('5e1'))
    assert_equal(Rational(50), Rational('5E1'))
    assert_equal(Rational(500), Rational('5e2'))
    assert_equal(Rational(5000), Rational('5e3'))
    assert_equal(Rational(500000000000), Rational('5e1_1'))

    assert_equal(Rational(0), ''.to_r)
    assert_equal(Rational(0), ' '.to_r)
    assert_equal(Rational(5), "\f\n\r\t\v5\0".to_r)
    assert_equal(Rational(0), '_'.to_r)
    assert_equal(Rational(0), '_5'.to_r)
    assert_equal(Rational(5), '5_'.to_r)
    assert_equal(Rational(5), '5x'.to_r)
    assert_equal(Rational(5), '5/_3'.to_r)
    assert_equal(Rational(5,3), '5/3_'.to_r)
    assert_equal(Rational(5,3), '5/3.3'.to_r)
    assert_equal(Rational(5,3), '5/3x'.to_r)
    assert_raise(ArgumentError){ Rational('')}
    assert_raise(ArgumentError){ Rational('_')}
    assert_raise(ArgumentError){ Rational("\f\n\r\t\v5\0")}
    assert_raise(ArgumentError){ Rational('_5')}
    assert_raise(ArgumentError){ Rational('5_')}
    assert_raise(ArgumentError){ Rational('5x')}
    assert_raise(ArgumentError){ Rational('5/_3')}
    assert_raise(ArgumentError){ Rational('5/3_')}
    assert_raise(ArgumentError){ Rational('5/3.3')}
    assert_raise(ArgumentError){ Rational('5/3x')}
  end

  def test_to_i
    assert_equal(1, Rational(3,2).to_i)
    assert_equal(1, Integer(Rational(3,2)))
  end

  def test_to_f
    assert_equal(1.5, Rational(3,2).to_f)
    assert_equal(1.5, Float(Rational(3,2)))
  end

  def test_to_c
    assert_equal(Complex(Rational(3,2)), Rational(3,2).to_c)
    assert_equal(Complex(Rational(3,2)), Complex(Rational(3,2)))
  end

  def test_to_r
    c = nil.to_r
    assert_equal([0,1], [c.numerator, c.denominator])

    c = 0.to_r
    assert_equal([0,1], [c.numerator, c.denominator])

    c = 1.to_r
    assert_equal([1,1], [c.numerator, c.denominator])

    c = 1.1.to_r
    assert_equal([2476979795053773, 2251799813685248],
		 [c.numerator, c.denominator])

    c = Rational(1,2).to_r
    assert_equal([1,2], [c.numerator, c.denominator])

    assert_raise(RangeError){Complex(1,2).to_r}

    if (0.0/0).nan?
      assert_raise(FloatDomainError){(0.0/0).to_r}
    end
    if (1.0/0).infinite?
      assert_raise(FloatDomainError){(1.0/0).to_r}
    end
  end

  def test_rationalize
    c = nil.rationalize
    assert_equal([0,1], [c.numerator, c.denominator])

    c = 0.rationalize
    assert_equal([0,1], [c.numerator, c.denominator])

    c = 1.rationalize
    assert_equal([1,1], [c.numerator, c.denominator])

    c = 1.1.rationalize
    assert_equal([11, 10], [c.numerator, c.denominator])

    c = Rational(1,2).rationalize
    assert_equal([1,2], [c.numerator, c.denominator])

    assert_equal(nil.rationalize(Rational(1,10)), Rational(0))
    assert_equal(0.rationalize(Rational(1,10)), Rational(0))
    assert_equal(10.rationalize(Rational(1,10)), Rational(10))

    r = 0.3333
    assert_equal(r.rationalize, Rational(3333, 10000))
    assert_equal(r.rationalize(Rational(1,10)), Rational(1,3))
    assert_equal(r.rationalize(Rational(-1,10)), Rational(1,3))

    r = Rational(5404319552844595,18014398509481984)
    assert_equal(r.rationalize, r)
    assert_equal(r.rationalize(Rational(1,10)), Rational(1,3))
    assert_equal(r.rationalize(Rational(-1,10)), Rational(1,3))

    r = -0.3333
    assert_equal(r.rationalize, Rational(-3333, 10000))
    assert_equal(r.rationalize(Rational(1,10)), Rational(-1,3))
    assert_equal(r.rationalize(Rational(-1,10)), Rational(-1,3))

    r = Rational(-5404319552844595,18014398509481984)
    assert_equal(r.rationalize, r)
    assert_equal(r.rationalize(Rational(1,10)), Rational(-1,3))
    assert_equal(r.rationalize(Rational(-1,10)), Rational(-1,3))

    assert_raise(RangeError){Complex(1,2).rationalize}

    if (0.0/0).nan?
      assert_raise(FloatDomainError){(0.0/0).rationalize}
    end
    if (1.0/0).infinite?
      assert_raise(FloatDomainError){(1.0/0).rationalize}
    end
  end

  def test_gcdlcm
    assert_equal(7, 91.gcd(-49))
    assert_equal(5, 5.gcd(0))
    assert_equal(5, 0.gcd(5))
    assert_equal(70, 14.lcm(35))
    assert_equal(0, 5.lcm(0))
    assert_equal(0, 0.lcm(5))
    assert_equal([5,0], 0.gcdlcm(5))
    assert_equal([5,0], 5.gcdlcm(0))

    assert_equal(1, 1073741827.gcd(1073741789))
    assert_equal(1152921470247108503, 1073741827.lcm(1073741789))

    assert_equal(1, 1073741789.gcd(1073741827))
    assert_equal(1152921470247108503, 1073741789.lcm(1073741827))
  end

  def test_supp
    assert_equal(true, 1.real?)
    assert_equal(true, 1.1.real?)

    assert_equal(1, 1.numerator)
    assert_equal(9, 9.numerator)
    assert_equal(1, 1.denominator)
    assert_equal(1, 9.denominator)

    assert_equal(1.0, 1.0.numerator)
    assert_equal(9.0, 9.0.numerator)
    assert_equal(1.0, 1.0.denominator)
    assert_equal(1.0, 9.0.denominator)

    assert_equal(Rational(1,2), 1.quo(2))
    assert_equal(Rational(5000000000), 10000000000.quo(2))
    assert_equal(0.5, 1.0.quo(2))
    assert_equal(Rational(1,4), Rational(1,2).quo(2))
    assert_equal(0, Rational(1,2).quo(Float::INFINITY))
    assert_predicate(Rational(1,2).quo(0.0), :infinite?, '[ruby-core:31626]')

    assert_equal(0.5, 1.fdiv(2))
    assert_equal(5000000000.0, 10000000000.fdiv(2))
    assert_equal(0.5, 1.0.fdiv(2))
    assert_equal(0.25, Rational(1,2).fdiv(2))
  end

  def test_ruby19
    assert_raise(NoMethodError){ Rational.new(1) }
    assert_raise(NoMethodError){ Rational.new!(1) }
  end

  def test_fixed_bug
    n = Float::MAX.to_i * 2
    assert_equal(1.0, Rational(n + 2, n + 1).to_f, '[ruby-dev:33852]')
  end

  def test_power_of_1_and_minus_1
    bug5715 = '[ruby-core:41498]'
    big = 1 << 66
    one = Rational( 1, 1)
    assert_eql  one,   one  ** -big     , bug5715
    assert_eql  one, (-one) ** -big     , bug5715
    assert_eql -one, (-one) ** -(big+1) , bug5715
    assert_equal Complex, ((-one) ** Rational(1,3)).class
  end

  def test_power_of_0
    bug5713 = '[ruby-core:41494]'
    big = 1 << 66
    zero = Rational(0, 1)
    assert_eql zero, zero ** big
    assert_eql zero, zero ** Rational(2, 3)
    assert_raise(ZeroDivisionError, bug5713) { Rational(0, 1) ** -big }
    assert_raise(ZeroDivisionError, bug5713) { Rational(0, 1) ** Rational(-2,3) }
  end

  def test_known_bug
  end

end
