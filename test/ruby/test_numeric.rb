require 'test/unit'
require_relative 'envutil'

class TestNumeric < Test::Unit::TestCase
  class DummyNumeric < Numeric
  end

  def assert_raise_with_message(exc, pattern, &blk)
    e = assert_raise(exc, &blk)
    assert_match(pattern, e.message)
  end

  def test_coerce
    a, b = 1.coerce(2)
    assert_equal(Fixnum, a.class)
    assert_equal(Fixnum, b.class)

    a, b = 1.coerce(2.0)
    assert_equal(Float, a.class)
    assert_equal(Float, b.class)

    assert_raise(TypeError) { -Numeric.new }

    assert_raise_with_message(TypeError, /can't be coerced into /) {1+:foo}
    assert_raise_with_message(TypeError, /can't be coerced into /) {1&:foo}
    assert_raise_with_message(TypeError, /can't be coerced into /) {1|:foo}
    assert_raise_with_message(TypeError, /can't be coerced into /) {1^:foo}

    EnvUtil.with_default_external(Encoding::UTF_8) do
      assert_raise_with_message(TypeError, /:\u{3042}/) {1+:"\u{3042}"}
      assert_raise_with_message(TypeError, /:\u{3042}/) {1&:"\u{3042}"}
      assert_raise_with_message(TypeError, /:\u{3042}/) {1|:"\u{3042}"}
      assert_raise_with_message(TypeError, /:\u{3042}/) {1^:"\u{3042}"}
    end
    EnvUtil.with_default_external(Encoding::US_ASCII) do
      assert_raise_with_message(TypeError, /:"\\u3042"/) {1+:"\u{3042}"}
      assert_raise_with_message(TypeError, /:"\\u3042"/) {1&:"\u{3042}"}
      assert_raise_with_message(TypeError, /:"\\u3042"/) {1|:"\u{3042}"}
      assert_raise_with_message(TypeError, /:"\\u3042"/) {1^:"\u{3042}"}
    end
  end

  def test_dummynumeric
    a = DummyNumeric.new

    DummyNumeric.class_eval do
      def coerce(x); nil; end
    end
    assert_raise(TypeError) { -a }
    assert_nil(1 <=> a)
    assert_raise(ArgumentError) { 1 <= a }

    DummyNumeric.class_eval do
      remove_method :coerce
      def coerce(x); 1.coerce(x); end
    end
    assert_equal(2, 1 + a)
    assert_equal(0, 1 <=> a)
    assert(1 <= a)

    DummyNumeric.class_eval do
      remove_method :coerce
      def coerce(x); [x, 1]; end
    end
    assert_equal(-1, -a)

  ensure
    DummyNumeric.class_eval do
      remove_method :coerce
    end
  end

  def test_singleton_method
    a = Numeric.new
    assert_raise_with_message(TypeError, /foo/) { def a.foo; end }
    assert_raise_with_message(TypeError, /\u3042/) { eval("def a.\u3042; end") }
  end

  def test_dup
    a = Numeric.new
    assert_raise(TypeError) { a.dup }

    c = Module.new do
      break eval("class C\u{3042} < Numeric; self; end")
    end
    assert_raise_with_message(TypeError, /C\u3042/) {c.new.dup}
  end

  def test_quo
    assert_raise(ArgumentError) {DummyNumeric.new.quo(1)}
  end

  def test_divmod
=begin
    DummyNumeric.class_eval do
      def /(x); 42.0; end
      def %(x); :mod; end
    end

    assert_equal(42, DummyNumeric.new.div(1))
    assert_equal(:mod, DummyNumeric.new.modulo(1))
    assert_equal([42, :mod], DummyNumeric.new.divmod(1))
=end

    assert_kind_of(Integer, 11.divmod(3.5).first, '[ruby-dev:34006]')

=begin
  ensure
    DummyNumeric.class_eval do
      remove_method :/, :%
    end
=end
  end

  def test_real_p
    assert(Numeric.new.real?)
  end

  def test_integer_p
    assert(!Numeric.new.integer?)
  end

  def test_abs
    a = DummyNumeric.new
    DummyNumeric.class_eval do
      def -@; :ok; end
      def <(x); true; end
    end

    assert_equal(:ok, a.abs)

    DummyNumeric.class_eval do
      remove_method :<
      def <(x); false; end
    end

    assert_equal(a, a.abs)

  ensure
    DummyNumeric.class_eval do
      remove_method :-@, :<
    end
  end

  def test_zero_p
    DummyNumeric.class_eval do
      def ==(x); true; end
    end

    assert(DummyNumeric.new.zero?)

  ensure
    DummyNumeric.class_eval do
      remove_method :==
    end
  end

  def test_to_int
    DummyNumeric.class_eval do
      def to_i; :ok; end
    end

    assert_equal(:ok, DummyNumeric.new.to_int)

  ensure
    DummyNumeric.class_eval do
      remove_method :to_i
    end
  end

  def test_cmp
    a = Numeric.new
    assert_equal(0, a <=> a)
    assert_nil(a <=> :foo)
  end

  def test_floor_ceil_round_truncate
    DummyNumeric.class_eval do
      def to_f; 1.5; end
    end

    a = DummyNumeric.new
    assert_equal(1, a.floor)
    assert_equal(2, a.ceil)
    assert_equal(2, a.round)
    assert_equal(1, a.truncate)

    DummyNumeric.class_eval do
      remove_method :to_f
      def to_f; 1.4; end
    end

    a = DummyNumeric.new
    assert_equal(1, a.floor)
    assert_equal(2, a.ceil)
    assert_equal(1, a.round)
    assert_equal(1, a.truncate)

    DummyNumeric.class_eval do
      remove_method :to_f
      def to_f; -1.5; end
    end

    a = DummyNumeric.new
    assert_equal(-2, a.floor)
    assert_equal(-1, a.ceil)
    assert_equal(-2, a.round)
    assert_equal(-1, a.truncate)

  ensure
    DummyNumeric.class_eval do
      remove_method :to_f
    end
  end

  def assert_step(expected, (from, *args), inf: false)
    enum = from.step(*args)
    size = enum.size
    xsize = expected.size

    if inf
      assert_send [size, :infinite?], "step size: +infinity"
      assert_send [size, :>, 0], "step size: +infinity"

      a = []
      from.step(*args) { |x| a << x; break if a.size == xsize }
      assert_equal expected, a, "step"

      a = []
      enum.each { |x| a << x; break if a.size == xsize }
      assert_equal expected, a, "step enumerator"
    else
      assert_equal expected.size, size, "step size"

      a = []
      from.step(*args) { |x| a << x }
      assert_equal expected, a, "step"

      a = []
      enum.each { |x| a << x }
      assert_equal expected, a, "step enumerator"
    end
  end

  def test_step
    i, bignum = 32, 1 << 30
    bignum <<= (i <<= 1) - 32 until bignum.is_a?(Bignum)
    assert_raise(ArgumentError) { 1.step(10, 1, 0) { } }
    assert_raise(ArgumentError) { 1.step(10, 0) { } }

    assert_equal(bignum*2+1, (-bignum).step(bignum, 1).size)
    assert_equal(bignum*2, (-bignum).step(bignum-1, 1).size)

    assert_equal(10+1, (0.0).step(10.0, 1.0).size)

    i, bigflo = 1, bignum.to_f
    i <<= 1 until (bigflo - i).to_i < bignum
    bigflo -= i >> 1
    assert_equal(bigflo.to_i, (0.0).step(bigflo-1.0, 1.0).size)
    assert_operator((0.0).step(bignum.to_f, 1.0).size, :>=, bignum) # may loose precision

    assert_step [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [1, 10]
    assert_step [1, 3, 5, 7, 9], [1, 10, 2]

    assert_step [10, 8, 6, 4, 2], [10, 1, -2]
    assert_step [1.0, 3.0, 5.0, 7.0, 9.0], [1.0, 10.0, 2.0]
    assert_step [1], [1, 10, bignum]

    assert_step [], [2, 1, 3]
    assert_step [], [-2, -1, -3]
    assert_step [10], [10, 1, -(bignum)]

    assert_step [], [1, 0, Float::INFINITY]
    assert_step [], [0, 1, -Float::INFINITY]
  end

  def test_num2long
    assert_raise(TypeError) { 1 & nil }
    assert_raise(TypeError) { 1 & 1.0 }
    assert_raise(TypeError) { 1 & 2147483648.0 }
    assert_raise(TypeError) { 1 & 9223372036854777856.0 }
    o = Object.new
    def o.to_int; 1; end
    assert_raise(TypeError) { assert_equal(1, 1 & o) }
  end

  def test_eql
    assert(1 == 1.0)
    assert(!(1.eql?(1.0)))
    assert(!(1.eql?(2)))
  end
end
