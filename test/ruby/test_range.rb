# frozen_string_literal: false
require 'test/unit'
require 'delegate'
require 'timeout'
require 'date'
require 'rbconfig/sizeof'

class TestRange < Test::Unit::TestCase
  def test_new
    assert_equal((0..2), Range.new(0, 2))
    assert_equal((0..2), Range.new(0, 2, false))
    assert_equal((0...2), Range.new(0, 2, true))

    assert_raise(ArgumentError) { (1.."3") }

    assert_equal((0..nil), Range.new(0, nil, false))
    assert_equal((0...nil), Range.new(0, nil, true))

    obj = Object.new
    def obj.<=>(other)
      raise RuntimeError, "cmp"
    end
    assert_raise_with_message(RuntimeError, "cmp") { (obj..3) }
  end

  def test_frozen_initialize
    r = Range.allocate
    r.freeze
    assert_raise(FrozenError){r.__send__(:initialize, 1, 2)}
  end

  def test_range_string
    # XXX: Is this really the test of Range?
    assert_equal([], ("a" ... "a").to_a)
    assert_equal(["a"], ("a" .. "a").to_a)
    assert_equal(["a"], ("a" ... "b").to_a)
    assert_equal(["a", "b"], ("a" .. "b").to_a)
    assert_equal([*"a".."z", "aa"], ("a"..).take(27))
  end

  def test_range_numeric_string
    assert_equal(["6", "7", "8"], ("6".."8").to_a, "[ruby-talk:343187]")
    assert_equal(["6", "7"], ("6"..."8").to_a)
    assert_equal(["9", "10"], ("9".."10").to_a)
    assert_equal(["9", "10"], ("9"..).take(2))
    assert_equal(["09", "10"], ("09".."10").to_a, "[ruby-dev:39361]")
    assert_equal(["9", "10"], (SimpleDelegator.new("9").."10").to_a)
    assert_equal(["9", "10"], (SimpleDelegator.new("9")..).take(2))
    assert_equal(["9", "10"], ("9"..SimpleDelegator.new("10")).to_a)
  end

  def test_range_symbol
    assert_equal([:a, :b], (:a .. :b).to_a)
  end

  def test_evaluation_order
    arr = [1,2]
    r = (arr.shift)..(arr.shift)
    assert_equal(1..2, r, "[ruby-dev:26383]")
  end

  class DuckRange
    def initialize(b,e,excl=false)
      @begin = b
      @end = e
      @excl = excl
    end
    attr_reader :begin, :end

    def exclude_end?
      @excl
    end
  end

  def test_duckrange
    assert_equal("bc", "abcd"[DuckRange.new(1,2)])
  end

  def test_min
    assert_equal(1, (1..2).min)
    assert_equal(nil, (2..1).min)
    assert_equal(1, (1...2).min)
    assert_equal(1, (1..).min)
    assert_raise(RangeError) { (..1).min }
    assert_raise(RangeError) { (...1).min }

    assert_equal(1.0, (1.0..2.0).min)
    assert_equal(nil, (2.0..1.0).min)
    assert_equal(1, (1.0...2.0).min)
    assert_equal(1, (1.0..).min)

    assert_equal(0, (0..0).min)
    assert_equal(nil, (0...0).min)

    assert_equal([0,1,2], (0..10).min(3))
    assert_equal([0,1], (0..1).min(3))
    assert_equal([0,1,2], (0..).min(3))
    assert_raise(RangeError) { (..1).min(3) }
    assert_raise(RangeError) { (...1).min(3) }

    assert_raise(RangeError) { (0..).min {|a, b| a <=> b } }
  end

  def test_max
    assert_equal(2, (1..2).max)
    assert_equal(nil, (2..1).max)
    assert_equal(1, (1...2).max)
    assert_raise(RangeError) { (1..).max }
    assert_raise(RangeError) { (1...).max }

    assert_equal(2.0, (1.0..2.0).max)
    assert_equal(nil, (2.0..1.0).max)
    assert_raise(TypeError) { (1.0...2.0).max }
    assert_raise(TypeError) { (1...1.5).max }
    assert_raise(TypeError) { (1.5...2).max }

    assert_equal(-0x80000002, ((-0x80000002)...(-0x80000001)).max)

    assert_equal(0, (0..0).max)
    assert_equal(nil, (0...0).max)

    assert_equal([10,9,8], (0..10).max(3))
    assert_equal([9,8,7], (0...10).max(3))
    assert_raise(RangeError) { (1..).max(3) }
    assert_raise(RangeError) { (1...).max(3) }

    assert_raise(RangeError) { (..0).min {|a, b| a <=> b } }

    assert_equal(2, (..2).max)
    assert_raise(TypeError) { (...2).max }
    assert_raise(TypeError) { (...2.0).max }

    assert_equal(Float::INFINITY, (1..Float::INFINITY).max)
    assert_nil((1..-Float::INFINITY).max)
  end

  def test_minmax
    assert_equal([1, 2], (1..2).minmax)
    assert_equal([nil, nil], (2..1).minmax)
    assert_equal([1, 1], (1...2).minmax)
    assert_raise(RangeError) { (1..).minmax }
    assert_raise(RangeError) { (1...).minmax }

    assert_equal([1.0, 2.0], (1.0..2.0).minmax)
    assert_equal([nil, nil], (2.0..1.0).minmax)
    assert_raise(TypeError) { (1.0...2.0).minmax }
    assert_raise(TypeError) { (1...1.5).minmax }
    assert_raise(TypeError) { (1.5...2).minmax }

    assert_equal([-0x80000002, -0x80000002], ((-0x80000002)...(-0x80000001)).minmax)

    assert_equal([0, 0], (0..0).minmax)
    assert_equal([nil, nil], (0...0).minmax)

    assert_equal([2, 1], (1..2).minmax{|a, b| b <=> a})

    assert_equal(['a', 'c'], ('a'..'c').minmax)
    assert_equal(['a', 'b'], ('a'...'c').minmax)

    assert_equal([1, Float::INFINITY], (1..Float::INFINITY).minmax)
    assert_equal([nil, nil], (1..-Float::INFINITY).minmax)
  end

  def test_initialize_twice
    r = eval("1..2")
    assert_raise(FrozenError) { r.instance_eval { initialize 3, 4 } }
    assert_raise(FrozenError) { r.instance_eval { initialize_copy 3..4 } }
  end

  def test_uninitialized_range
    r = Range.allocate
    s = Marshal.dump(r)
    r = Marshal.load(s)
    assert_nothing_raised { r.instance_eval { initialize 5, 6} }
  end

  def test_marshal
    r = 1..2
    assert_equal(r, Marshal.load(Marshal.dump(r)))
    r = 1...2
    assert_equal(r, Marshal.load(Marshal.dump(r)))
    r = (1..)
    assert_equal(r, Marshal.load(Marshal.dump(r)))
    r = (1...)
    assert_equal(r, Marshal.load(Marshal.dump(r)))
  end

  def test_bad_value
    assert_raise(ArgumentError) { (1 .. :a) }
  end

  def test_exclude_end
    assert_not_predicate(0..1, :exclude_end?)
    assert_predicate(0...1, :exclude_end?)
    assert_not_predicate(0.., :exclude_end?)
    assert_predicate(0..., :exclude_end?)
  end

  def test_eq
    r = (0..1)
    assert_equal(r, r)
    assert_equal(r, (0..1))
    assert_not_equal(r, 0)
    assert_not_equal(r, (1..2))
    assert_not_equal(r, (0..2))
    assert_not_equal(r, (0...1))
    assert_not_equal(r, (0..nil))
    subclass = Class.new(Range)
    assert_equal(r, subclass.new(0,1))

    r = (0..nil)
    assert_equal(r, r)
    assert_equal(r, (0..nil))
    assert_not_equal(r, 0)
    assert_not_equal(r, (0...nil))
    subclass = Class.new(Range)
    assert_equal(r, subclass.new(0,nil))
  end

  def test_eql
    r = (0..1)
    assert_operator(r, :eql?, r)
    assert_operator(r, :eql?, 0..1)
    assert_not_operator(r, :eql?, 0)
    assert_not_operator(r, :eql?, 1..2)
    assert_not_operator(r, :eql?, 0..2)
    assert_not_operator(r, :eql?, 0...1)
    subclass = Class.new(Range)
    assert_operator(r, :eql?, subclass.new(0,1))

    r = (0..nil)
    assert_operator(r, :eql?, r)
    assert_operator(r, :eql?, 0..nil)
    assert_not_operator(r, :eql?, 0)
    assert_not_operator(r, :eql?, 0...nil)
    subclass = Class.new(Range)
    assert_operator(r, :eql?, subclass.new(0,nil))
  end

  def test_hash
    assert_kind_of(Integer, (0..1).hash)
    assert_equal((0..1).hash, (0..1).hash)
    assert_not_equal((0..1).hash, (0...1).hash)
    assert_equal((0..nil).hash, (0..nil).hash)
    assert_not_equal((0..nil).hash, (0...nil).hash)
    assert_kind_of(String, (0..1).hash.to_s)
  end

  def test_step_numeric_range
    # Fixnums, floats and all other numbers (like rationals) should behave exactly the same,
    # but the behavior is implemented independently in 3 different branches of code,
    # so we need to test each of them.
    %i[to_i to_r to_f].each do |type|
      conv = type.to_proc

      from = conv.(0)
      to = conv.(10)
      step = conv.(2)

      # finite
      a = []
      (from..to).step(step) {|x| a << x }
      assert_equal([0, 2, 4, 6, 8, 10].map(&conv), a)

      a = []
      (from...to).step(step) {|x| a << x }
      assert_equal([0, 2, 4, 6, 8].map(&conv), a)

      # Note: ArithmeticSequence behavior tested in its own test, but we also put it here
      # to demonstrate the result is the same
      assert_kind_of(Enumerator::ArithmeticSequence, (from..to).step(step))
      assert_equal([0, 2, 4, 6, 8, 10].map(&conv), (from..to).step(step).to_a)
      assert_kind_of(Enumerator::ArithmeticSequence, (from...to).step(step))
      assert_equal([0, 2, 4, 6, 8].map(&conv), (from...to).step(step).to_a)

      # endless
      a = []
      (from..).step(step) {|x| a << x; break if a.size == 5 }
      assert_equal([0, 2, 4, 6, 8].map(&conv), a)

      assert_kind_of(Enumerator::ArithmeticSequence, (from..).step(step))
      assert_equal([0, 2, 4, 6, 8].map(&conv), (from..).step(step).take(5))

      # beginless
      assert_raise(ArgumentError) { (..to).step(step) {} }
      assert_kind_of(Enumerator::ArithmeticSequence, (..to).step(step))
      # This is inconsistent, but so it is implemented by ArithmeticSequence
      assert_raise(TypeError) { (..to).step(step).to_a }

      # negative step

      a = []
      (from..to).step(-step) {|x| a << x }
      assert_equal([], a)

      a = []
      (from..-to).step(-step) {|x| a << x }
      assert_equal([0, -2, -4, -6, -8, -10].map(&conv), a)

      a = []
      (from...-to).step(-step) {|x| a << x }
      assert_equal([0, -2, -4, -6, -8].map(&conv), a)

      a = []
      (from...).step(-step) {|x| a << x; break if a.size == 5 }
      assert_equal([0, -2, -4, -6, -8].map(&conv), a)

      assert_kind_of(Enumerator::ArithmeticSequence, (from..to).step(-step))
      assert_equal([], (from..to).step(-step).to_a)

      assert_kind_of(Enumerator::ArithmeticSequence, (from..-to).step(-step))
      assert_equal([0, -2, -4, -6, -8, -10].map(&conv), (from..-to).step(-step).to_a)

      assert_kind_of(Enumerator::ArithmeticSequence, (from...-to).step(-step))
      assert_equal([0, -2, -4, -6, -8].map(&conv), (from...-to).step(-step).to_a)

      assert_kind_of(Enumerator::ArithmeticSequence, (from...).step(-step))
      assert_equal([0, -2, -4, -6, -8].map(&conv), (from...).step(-step).take(5))

      # zero step

      assert_raise(ArgumentError) { (from..to).step(0) {} }
      assert_raise(ArgumentError) { (from..to).step(0) }

      # default step

      a = []
      (from..to).step {|x| a << x }
      assert_equal([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(&conv), a)

      assert_kind_of(Enumerator::ArithmeticSequence, (from..to).step)
      assert_equal([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(&conv), (from..to).step.to_a)

      # default + endless range
      a = []
      (from..).step {|x| a << x; break if a.size == 5 }
      assert_equal([0, 1, 2, 3, 4].map(&conv), a)

      assert_kind_of(Enumerator::ArithmeticSequence, (from..).step)
      assert_equal([0, 1, 2, 3, 4].map(&conv), (from..).step.take(5))

      # default + beginless range
      assert_kind_of(Enumerator::ArithmeticSequence, (..to).step)

      # step is not numeric

      to = conv.(5)

      val = Struct.new(:val)

      a = []
      assert_raise(TypeError) { (from..to).step(val.new(step)) {|x| a << x } }
      assert_kind_of(Enumerator, (from..to).step(val.new(step)))
      assert_raise(TypeError) { (from..to).step(val.new(step)).to_a }

      # step is not numeric, but coercible
      val = Struct.new(:val) do
        def coerce(num) = [self.class.new(num), self]
        def +(other) = self.class.new(val + other.val)
        def <=>(other) = other.is_a?(self.class) ? val <=> other.val : val <=> other
      end

      a = []
      (from..to).step(val.new(step)) {|x| a << x }
      assert_equal([from, val.new(conv.(2)), val.new(conv.(4))], a)

      assert_kind_of(Enumerator, (from..to).step(val.new(step)))
      assert_equal([from, val.new(conv.(2)), val.new(conv.(4))], (from..to).step(val.new(step)).to_a)
    end
  end

  def test_step_numeric_fixnum_boundary
    a = []
    (2**32-1 .. 2**32+1).step(2) {|x| a << x }
    assert_equal([4294967295, 4294967297], a)

    zero = (2**32).coerce(0).first
    assert_raise(ArgumentError) { (2**32-1 .. 2**32+1).step(zero) }
    assert_raise(ArgumentError) { (2**32-1 .. 2**32+1).step(zero) { } }

    a = []
    (2**32-1 .. ).step(2) {|x| a << x; break if a.size == 2 }
    assert_equal([4294967295, 4294967297], a)

    max = RbConfig::LIMITS["FIXNUM_MAX"]
    a = []
    (max..).step {|x| a << x; break if a.size == 2 }
    assert_equal([max, max+1], a)

    a = []
    (max..).step(max) {|x| a << x; break if a.size == 4 }
    assert_equal([max, 2*max, 3*max, 4*max], a)
  end

  def test_step_big_float
    a = []
    (0x40000000..0x40000002).step(0.5) {|x| a << x }
    assert_equal([1073741824, 1073741824.5, 1073741825.0, 1073741825.5, 1073741826], a)
  end

  def test_step_non_numeric_range
    # finite
    a = []
    ('a'..'aaaa').step('a') { a << _1 }
    assert_equal(%w[a aa aaa aaaa], a)

    assert_kind_of(Enumerator, ('a'..'aaaa').step('a'))
    assert_equal(%w[a aa aaa aaaa], ('a'..'aaaa').step('a').to_a)

    a = []
    ('a'...'aaaa').step('a') { a << _1 }
    assert_equal(%w[a aa aaa], a)

    assert_kind_of(Enumerator, ('a'...'aaaa').step('a'))
    assert_equal(%w[a aa aaa], ('a'...'aaaa').step('a').to_a)

    # endless
    a = []
    ('a'...).step('a') { a << _1; break if a.size == 3 }
    assert_equal(%w[a aa aaa], a)

    assert_kind_of(Enumerator, ('a'...).step('a'))
    assert_equal(%w[a aa aaa], ('a'...).step('a').take(3))

    # beginless
    assert_raise(ArgumentError) { (...'aaa').step('a') {} }
    assert_raise(ArgumentError) { (...'aaa').step('a') }

    # step is not provided
    assert_raise(ArgumentError) { (Time.new(2022)...Time.new(2023)).step }

    # step is incompatible
    assert_raise(TypeError) { (Time.new(2022)...Time.new(2023)).step('a') {} }
    assert_raise(TypeError) { (Time.new(2022)...Time.new(2023)).step('a').to_a }

    # step is compatible, but shouldn't convert into numeric domain:
    a = []
    (Time.utc(2022, 2, 24)...).step(1) { a << _1; break if a.size == 2 }
    assert_equal([Time.utc(2022, 2, 24), Time.utc(2022, 2, 24, 0, 0, 1)], a)

    a = []
    (Time.utc(2022, 2, 24)...).step(1.0) { a << _1; break if a.size == 2 }
    assert_equal([Time.utc(2022, 2, 24), Time.utc(2022, 2, 24, 0, 0, 1)], a)

    a = []
    (Time.utc(2022, 2, 24)...).step(1r) { a << _1; break if a.size == 2 }
    assert_equal([Time.utc(2022, 2, 24), Time.utc(2022, 2, 24, 0, 0, 1)], a)

    # step decreases the value
    a = []
    (Time.utc(2022, 2, 24)...).step(-1) { a << _1; break if a.size == 2 }
    assert_equal([Time.utc(2022, 2, 24), Time.utc(2022, 2, 23, 23, 59, 59)], a)

    a = []
    (Time.utc(2022, 2, 24)...Time.utc(2022, 2, 23, 23, 59, 57)).step(-1) { a << _1 }
    assert_equal([Time.utc(2022, 2, 24), Time.utc(2022, 2, 23, 23, 59, 59),
                  Time.utc(2022, 2, 23, 23, 59, 58)], a)

    a = []
    (Time.utc(2022, 2, 24)..Time.utc(2022, 2, 23, 23, 59, 57)).step(-1) { a << _1 }
    assert_equal([Time.utc(2022, 2, 24), Time.utc(2022, 2, 23, 23, 59, 59),
                  Time.utc(2022, 2, 23, 23, 59, 58), Time.utc(2022, 2, 23, 23, 59, 57)], a)

    # step decreases, but the range is forward-directed:
    a = []
    (Time.utc(2022, 2, 24)...Time.utc(2022, 2, 24, 01, 01, 03)).step(-1) { a << _1 }
    assert_equal([], a)
  end

  def test_step_string_legacy
    # finite
    a = []
    ('a'..'g').step(2) { a << _1 }
    assert_equal(%w[a c e g], a)

    assert_kind_of(Enumerator, ('a'..'g').step(2))
    assert_equal(%w[a c e g], ('a'..'g').step(2).to_a)

    a = []
    ('a'...'g').step(2) { a << _1 }
    assert_equal(%w[a c e], a)

    assert_kind_of(Enumerator, ('a'...'g').step(2))
    assert_equal(%w[a c e], ('a'...'g').step(2).to_a)

    # endless
    a = []
    ('a'...).step(2) { a << _1; break if a.size == 3 }
    assert_equal(%w[a c e], a)

    assert_kind_of(Enumerator, ('a'...).step(2))
    assert_equal(%w[a c e], ('a'...).step(2).take(3))

    # beginless
    assert_raise(ArgumentError) { (...'g').step(2) {} }
    assert_raise(ArgumentError) { (...'g').step(2) }

    # step is not provided
    a = []
    ('a'..'d').step { a << _1 }
    assert_equal(%w[a b c d], a)

    assert_kind_of(Enumerator, ('a'..'d').step)
    assert_equal(%w[a b c d], ('a'..'d').step.to_a)

    a = []
    ('a'...'d').step { a << _1 }
    assert_equal(%w[a b c], a)

    assert_kind_of(Enumerator, ('a'...'d').step)
    assert_equal(%w[a b c], ('a'...'d').step.to_a)

    # endless
    a = []
    ('a'...).step { a << _1; break if a.size == 3 }
    assert_equal(%w[a b c], a)

    assert_kind_of(Enumerator, ('a'...).step)
    assert_equal(%w[a b c], ('a'...).step.take(3))
  end

  def test_step_symbol_legacy
    # finite
    a = []
    (:a..:g).step(2) { a << _1 }
    assert_equal(%i[a c e g], a)

    assert_kind_of(Enumerator, (:a..:g).step(2))
    assert_equal(%i[a c e g], (:a..:g).step(2).to_a)

    a = []
    (:a...:g).step(2) { a << _1 }
    assert_equal(%i[a c e], a)

    assert_kind_of(Enumerator, (:a...:g).step(2))
    assert_equal(%i[a c e], (:a...:g).step(2).to_a)

    # endless
    a = []
    (:a...).step(2) { a << _1; break if a.size == 3 }
    assert_equal(%i[a c e], a)

    assert_kind_of(Enumerator, (:a...).step(2))
    assert_equal(%i[a c e], (:a...).step(2).take(3))

    # beginless
    assert_raise(ArgumentError) { (...:g).step(2) {} }
    assert_raise(ArgumentError) { (...:g).step(2) }

    # step is not provided
    a = []
    (:a..:d).step { a << _1 }
    assert_equal(%i[a b c d], a)

    assert_kind_of(Enumerator, (:a..:d).step)
    assert_equal(%i[a b c d], (:a..:d).step.to_a)

    a = []
    (:a...:d).step { a << _1 }
    assert_equal(%i[a b c], a)

    assert_kind_of(Enumerator, (:a...:d).step)
    assert_equal(%i[a b c], (:a...:d).step.to_a)

    # endless
    a = []
    (:a...).step { a << _1; break if a.size == 3 }
    assert_equal(%i[a b c], a)

    assert_kind_of(Enumerator, (:a...).step)
    assert_equal(%i[a b c], (:a...).step.take(3))
  end

  def test_step_bug15537
    assert_equal([10.0, 9.0, 8.0, 7.0], (10 ..).step(-1.0).take(4))
    assert_equal([10.0, 9.0, 8.0, 7.0], (10.0 ..).step(-1).take(4))
  end

  def test_percent_step
    aseq = (1..10) % 2
    assert_equal(Enumerator::ArithmeticSequence, aseq.class)
    assert_equal(1, aseq.begin)
    assert_equal(10, aseq.end)
    assert_equal(2, aseq.step)
    assert_equal([1, 3, 5, 7, 9], aseq.to_a)
  end

  def test_step_ruby_core_35753
    assert_equal(6, (1...6.3).step.to_a.size)
    assert_equal(5, (1.1...6).step.to_a.size)
    assert_equal(5, (1...6).step(1.1).to_a.size)
    assert_equal(3, (1.0...5.4).step(1.5).to_a.size)
    assert_equal(3, (1.0...5.5).step(1.5).to_a.size)
    assert_equal(4, (1.0...5.6).step(1.5).to_a.size)
  end

  def test_each
    a = []
    (0..10).each {|x| a << x }
    assert_equal([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], a)

    a = []
    (0..).each {|x| a << x; break if a.size == 10 }
    assert_equal([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], a)

    o1 = Object.new
    o2 = Object.new
    def o1.setcmp(v) @cmpresult = v end
    o1.setcmp(-1)
    def o1.<=>(x); @cmpresult; end
    def o2.setcmp(v) @cmpresult = v end
    o2.setcmp(0)
    def o2.<=>(x); @cmpresult; end
    class << o1; self; end.class_eval do
      define_method(:succ) { o2 }
    end

    r1 = (o1..o2)
    r2 = (o1...o2)

    a = []
    r1.each {|x| a << x }
    assert_equal([o1, o2], a)

    a = []
    r2.each {|x| a << x }
    assert_equal([o1], a)

    o2.setcmp(1)

    a = []
    r1.each {|x| a << x }
    assert_equal([o1], a)

    o2.setcmp(nil)

    a = []
    r1.each {|x| a << x }
    assert_equal([o1], a)

    o1.setcmp(nil)

    a = []
    r2.each {|x| a << x }
    assert_equal([], a)

    o = Object.new
    class << o
      def to_str() "a" end
      def <=>(other) to_str <=> other end
    end

    a = []
    (o.."c").each {|x| a << x}
    assert_equal(["a", "b", "c"], a)
    a = []
    (o..).each {|x| a << x; break if a.size >= 3}
    assert_equal(["a", "b", "c"], a)
  end

  def test_each_with_succ
    c = Struct.new(:i) do
      def succ; self.class.new(i+1); end
      def <=>(other) i <=> other.i;end
    end.new(0)

    result = []
    (c..c.succ).each do |d|
      result << d.i
    end
    assert_equal([0, 1], result)

    result = []
    (c..).each do |d|
      result << d.i
      break if d.i >= 4
    end
    assert_equal([0, 1, 2, 3, 4], result)
  end

  def test_reverse_each
    a = []
    (1..3).reverse_each {|x| a << x }
    assert_equal([3, 2, 1], a)

    a = []
    (1...3).reverse_each {|x| a << x }
    assert_equal([2, 1], a)

    fmax = RbConfig::LIMITS['FIXNUM_MAX']
    fmin = RbConfig::LIMITS['FIXNUM_MIN']

    a = []
    (fmax+1..fmax+3).reverse_each {|x| a << x }
    assert_equal([fmax+3, fmax+2, fmax+1], a)

    a = []
    (fmax+1...fmax+3).reverse_each {|x| a << x }
    assert_equal([fmax+2, fmax+1], a)

    a = []
    (fmax-1..fmax+1).reverse_each {|x| a << x }
    assert_equal([fmax+1, fmax, fmax-1], a)

    a = []
    (fmax-1...fmax+1).reverse_each {|x| a << x }
    assert_equal([fmax, fmax-1], a)

    a = []
    (fmin-1..fmin+1).reverse_each{|x| a << x }
    assert_equal([fmin+1, fmin, fmin-1], a)

    a = []
    (fmin-1...fmin+1).reverse_each{|x| a << x }
    assert_equal([fmin, fmin-1], a)

    a = []
    (fmin-3..fmin-1).reverse_each{|x| a << x }
    assert_equal([fmin-1, fmin-2, fmin-3], a)

    a = []
    (fmin-3...fmin-1).reverse_each{|x| a << x }
    assert_equal([fmin-2, fmin-3], a)

    a = []
    ("a".."c").reverse_each {|x| a << x }
    assert_equal(["c", "b", "a"], a)
  end

  def test_reverse_each_for_beginless_range
    fmax = RbConfig::LIMITS['FIXNUM_MAX']
    fmin = RbConfig::LIMITS['FIXNUM_MIN']

    a = []
    (..3).reverse_each {|x| a << x; break if x <= 0 }
    assert_equal([3, 2, 1, 0], a)

    a = []
    (...3).reverse_each {|x| a << x; break if x <= 0 }
    assert_equal([2, 1, 0], a)

    a = []
    (..fmax+1).reverse_each {|x| a << x; break if x <= fmax-1 }
    assert_equal([fmax+1, fmax, fmax-1], a)

    a = []
    (...fmax+1).reverse_each {|x| a << x; break if x <= fmax-1 }
    assert_equal([fmax, fmax-1], a)

    a = []
    (..fmin+1).reverse_each {|x| a << x; break if x <= fmin-1 }
    assert_equal([fmin+1, fmin, fmin-1], a)

    a = []
    (...fmin+1).reverse_each {|x| a << x; break if x <= fmin-1 }
    assert_equal([fmin, fmin-1], a)

    a = []
    (..fmin-1).reverse_each {|x| a << x; break if x <= fmin-3 }
    assert_equal([fmin-1, fmin-2, fmin-3], a)

    a = []
    (...fmin-1).reverse_each {|x| a << x; break if x <= fmin-3 }
    assert_equal([fmin-2, fmin-3], a)
  end

  def test_reverse_each_for_endless_range
    assert_raise(TypeError) { (1..).reverse_each {} }

    enum = nil
    assert_nothing_raised { enum = (1..).reverse_each }
    assert_raise(TypeError) { enum.each {} }
  end

  def test_reverse_each_for_single_point_range
    fmin = RbConfig::LIMITS['FIXNUM_MIN']
    fmax = RbConfig::LIMITS['FIXNUM_MAX']

    values = [fmin*2, fmin-1, fmin, 0, fmax, fmax+1, fmax*2]

    values.each do |b|
      r = b..b
      a = []
      r.reverse_each {|x| a << x }
      assert_equal([b], a, "failed on #{r}")

      r = b...b+1
      a = []
      r.reverse_each {|x| a << x }
      assert_equal([b], a, "failed on #{r}")
    end
  end

  def test_reverse_each_for_empty_range
    fmin = RbConfig::LIMITS['FIXNUM_MIN']
    fmax = RbConfig::LIMITS['FIXNUM_MAX']

    values = [fmin*2, fmin-1, fmin, 0, fmax, fmax+1, fmax*2]

    values.each do |b|
      r = b..b-1
      a = []
      r.reverse_each {|x| a << x }
      assert_equal([], a, "failed on #{r}")
    end

    values.repeated_permutation(2).to_a.product([true, false]).each do |(b, e), excl|
      next unless b > e || (b == e && excl)

      r = Range.new(b, e, excl)
      a = []
      r.reverse_each {|x| a << x }
      assert_equal([], a, "failed on #{r}")
    end
  end

  def test_reverse_each_with_no_block
    enum = (1..5).reverse_each
    assert_equal 5, enum.size

    a = []
    enum.each {|x| a << x }
    assert_equal [5, 4, 3, 2, 1], a
  end

  def test_reverse_each_size
    assert_equal(3, (1..3).reverse_each.size)
    assert_equal(3, (1..3.3).reverse_each.size)
    assert_raise(TypeError) { (1..nil).reverse_each.size }
    assert_raise(TypeError) { (1.1..3).reverse_each.size }
    assert_raise(TypeError) { (1.1..3.3).reverse_each.size }
    assert_raise(TypeError) { (1.1..nil).reverse_each.size }
    assert_equal(Float::INFINITY, (..3).reverse_each.size)
    assert_raise(TypeError) { (nil..3.3).reverse_each.size }
    assert_raise(TypeError) { (nil..nil).reverse_each.size }

    assert_equal(2, (1...3).reverse_each.size)
    assert_equal(3, (1...3.3).reverse_each.size)

    assert_equal(nil, ('a'..'z').reverse_each.size)
    assert_raise(TypeError) { ('a'..).reverse_each.size }
    assert_raise(TypeError) { (..'z').reverse_each.size }
  end

  def test_begin_end
    assert_equal(0, (0..1).begin)
    assert_equal(1, (0..1).end)
    assert_equal(1, (0...1).end)
    assert_equal(0, (0..nil).begin)
    assert_equal(nil, (0..nil).end)
    assert_equal(nil, (0...nil).end)
  end

  def test_first_last
    assert_equal([0, 1, 2], (0..10).first(3))
    assert_equal([8, 9, 10], (0..10).last(3))
    assert_equal(0, (0..10).first)
    assert_equal(10, (0..10).last)
    assert_equal("a", ("a".."c").first)
    assert_equal("c", ("a".."c").last)
    assert_equal(0, (2..0).last)

    assert_equal([0, 1, 2], (0...10).first(3))
    assert_equal([7, 8, 9], (0...10).last(3))
    assert_equal(0, (0...10).first)
    assert_equal(10, (0...10).last)
    assert_equal("a", ("a"..."c").first)
    assert_equal("c", ("a"..."c").last)
    assert_equal(0, (2...0).last)

    assert_equal([0, 1, 2], (0..nil).first(3))
    assert_equal(0, (0..nil).first)
    assert_equal("a", ("a"..nil).first)
    assert_raise(RangeError) { (0..nil).last }
    assert_raise(RangeError) { (0..nil).last(3) }
    assert_raise(RangeError) { (nil..0).first }
    assert_raise(RangeError) { (nil..0).first(3) }

    assert_equal([0, 1, 2], (0..10).first(3.0))
    assert_equal([8, 9, 10], (0..10).last(3.0))
    assert_raise(TypeError) { (0..10).first("3") }
    assert_raise(TypeError) { (0..10).last("3") }
    class << (o = Object.new)
      def to_int; 3; end
    end
    assert_equal([0, 1, 2], (0..10).first(o))
    assert_equal([8, 9, 10], (0..10).last(o))

    assert_raise(ArgumentError) { (0..10).first(-1) }
    assert_raise(ArgumentError) { (0..10).last(-1) }
  end

  def test_last_with_redefine_each
    assert_in_out_err([], <<-'end;', ['true'], [])
      class Range
        remove_method :each
        def each(&b)
          [1, 2, 3, 4, 5].each(&b)
        end
      end
      puts [3, 4, 5] == (1..10).last(3)
    end;
  end

  def test_to_s
    assert_equal("0..1", (0..1).to_s)
    assert_equal("0...1", (0...1).to_s)
    assert_equal("0..", (0..nil).to_s)
    assert_equal("0...", (0...nil).to_s)
  end

  def test_inspect
    assert_equal("0..1", (0..1).inspect)
    assert_equal("0...1", (0...1).inspect)
    assert_equal("0..", (0..nil).inspect)
    assert_equal("0...", (0...nil).inspect)
    assert_equal("..1", (nil..1).inspect)
    assert_equal("...1", (nil...1).inspect)
    assert_equal("nil..nil", (nil..nil).inspect)
    assert_equal("nil...nil", (nil...nil).inspect)
  end

  def test_eqq
    assert_operator(0..10, :===, 5)
    assert_not_operator(0..10, :===, 11)
    assert_operator(5..nil, :===, 11)
    assert_not_operator(5..nil, :===, 0)
    assert_operator(nil..10, :===, 0)
    assert_operator(nil..nil, :===, 0)
    assert_operator(nil..nil, :===, Object.new)
    assert_not_operator(0..10, :===, 0..10)
  end

  def test_eqq_string
    assert_operator('A'..'Z', :===, 'ANA')
    assert_not_operator('A'..'Z', :===, 'ana')
    assert_operator('A'.., :===, 'ANA')
    assert_operator(..'Z', :===, 'ANA')
    assert_operator(nil..nil, :===, 'ANA')
  end

  def test_eqq_time
    bug11113 = '[ruby-core:69052] [Bug #11113]'
    t = Time.now
    assert_nothing_raised(TypeError, bug11113) {
      assert_operator(t..(t+10), :===, t+5)
      assert_operator(t.., :===, t+5)
      assert_not_operator(t.., :===, t-5)
    }
  end

  def test_eqq_non_linear
    bug12003 = '[ruby-core:72908] [Bug #12003]'
    c = Class.new {
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def succ
        self.class.new(@value.succ)
      end

      def ==(other)
        @value == other.value
      end

      def <=>(other)
        @value <=> other.value
      end
    }
    assert_operator(c.new(0)..c.new(10), :===, c.new(5), bug12003)
  end

  def test_eqq_unbounded_ruby_bug_19864
    t1 = Date.today
    t2 = t1 + 1
    assert_equal(true, (..t1) === t1)
    assert_equal(false, (..t1) === t2)
    assert_equal(true, (..t2) === t1)
    assert_equal(true, (..t2) === t2)
    assert_equal(false, (...t1) === t1)
    assert_equal(false, (...t1) === t2)
    assert_equal(true, (...t2) === t1)
    assert_equal(false, (...t2) === t2)

    assert_equal(true, (t1..) === t1)
    assert_equal(true, (t1..) === t2)
    assert_equal(false, (t2..) === t1)
    assert_equal(true, (t2..) === t2)
    assert_equal(true, (t1...) === t1)
    assert_equal(true, (t1...) === t2)
    assert_equal(false, (t2...) === t1)
    assert_equal(true, (t2...) === t2)
  end

  def test_eqq_non_iteratable
    k = Class.new do
      include Comparable
      attr_reader :i
      def initialize(i) @i = i; end
      def <=>(o); i <=> o.i; end
    end
    assert_operator(k.new(0)..k.new(2), :===, k.new(1))
  end

  def test_include
    assert_include("a".."z", "c")
    assert_not_include("a".."z", "5")
    assert_include("a"..."z", "y")
    assert_not_include("a"..."z", "z")
    assert_not_include("a".."z", "cc")
    assert_raise(TypeError) {("a"..).include?("c")}
    assert_raise(TypeError) {("a"..).include?("5")}

    assert_include(0...10, 5)
    assert_include(5..., 10)
    assert_not_include(5..., 0)
    assert_raise(TypeError) {(.."z").include?("z")}
    assert_raise(TypeError) {(..."z").include?("z")}
    assert_include(..10, 10)
    assert_not_include(...10, 10)
  end

  def test_cover
    assert_operator("a".."z", :cover?, "c")
    assert_not_operator("a".."z", :cover?, "5")
    assert_operator("a"..."z", :cover?, "y")
    assert_not_operator("a"..."z", :cover?, "z")
    assert_operator("a".."z", :cover?, "cc")
    assert_not_operator(5..., :cover?, 0)
    assert_not_operator(5..., :cover?, "a")
    assert_operator(5.., :cover?, 10)

    assert_operator(2..5, :cover?, 2..5)
    assert_operator(2...6, :cover?, 2...6)
    assert_operator(2...6, :cover?, 2..5)
    assert_operator(2..5, :cover?, 2...6)
    assert_operator(2..5, :cover?, 2..4)
    assert_operator(2..5, :cover?, 2...4)
    assert_operator(2..5, :cover?, 2...5)
    assert_operator(2..5, :cover?, 3..5)
    assert_operator(2..5, :cover?, 3..4)
    assert_operator(2..5, :cover?, 3...6)
    assert_operator(2...6, :cover?, 2...5)
    assert_operator(2...6, :cover?, 2..5)
    assert_operator(2..6, :cover?, 2...6)
    assert_operator(2.., :cover?, 2..)
    assert_operator(2.., :cover?, 3..)
    assert_operator(1.., :cover?, 1..10)
    assert_operator(..2, :cover?, ..2)
    assert_operator(..2, :cover?, ..1)
    assert_operator(..2, :cover?, 0..1)
    assert_operator(2.0..5.0, :cover?, 2..3)
    assert_operator(2..5, :cover?, 2.0..3.0)
    assert_operator(2..5, :cover?, 2.0...3.0)
    assert_operator(2..5, :cover?, 2.0...5.0)
    assert_operator(2.0..5.0, :cover?, 2.0...3.0)
    assert_operator(2.0..5.0, :cover?, 2.0...5.0)
    assert_operator('aa'..'zz', :cover?, 'aa'...'bb')

    assert_not_operator(2..5, :cover?, 1..5)
    assert_not_operator(2...6, :cover?, 1..5)
    assert_not_operator(2..5, :cover?, 1...6)
    assert_not_operator(1..3, :cover?, 1...6)
    assert_not_operator(2..5, :cover?, 2..6)
    assert_not_operator(2...6, :cover?, 2..6)
    assert_not_operator(2...6, :cover?, 2...7)
    assert_not_operator(2..3, :cover?, 1..4)
    assert_not_operator(1..2, :cover?, 1.0..3.0)
    assert_not_operator(1.0..2.9, :cover?, 1.0..3.0)
    assert_not_operator(1..2, :cover?, 4..3)
    assert_not_operator(2..1, :cover?, 1..2)
    assert_not_operator(1...2, :cover?, 1...3)
    assert_not_operator(2.., :cover?, 1..)
    assert_not_operator(2.., :cover?, 1..10)
    assert_not_operator(2.., :cover?, ..10)
    assert_not_operator(1..10, :cover?, 1..)
    assert_not_operator(1..10, :cover?, ..1)
    assert_not_operator(1..5, :cover?, 3..2)
    assert_not_operator(1..10, :cover?, 3...2)
    assert_not_operator(1..10, :cover?, 3...3)
    assert_not_operator('aa'..'zz', :cover?, 'aa'...'zzz')
    assert_not_operator(1..10, :cover?, 1...10.1)

    assert_operator(..2, :cover?, 1)
    assert_operator(..2, :cover?, 2)
    assert_not_operator(..2, :cover?, 3)
    assert_not_operator(...2, :cover?, 2)
    assert_not_operator(..2, :cover?, "2")
    assert_operator(..2, :cover?, ..2)
    assert_operator(..2, :cover?, ...2)
    assert_not_operator(..2, :cover?, .."2")
    assert_not_operator(...2, :cover?, ..2)

    assert_not_operator(2.., :cover?, 1)
    assert_operator(2.., :cover?, 2)
    assert_operator(2..., :cover?, 3)
    assert_operator(2.., :cover?, 2)
    assert_not_operator(2.., :cover?, "2")
    assert_operator(2.., :cover?, 2..)
    assert_operator(2.., :cover?, 2...)
    assert_not_operator(2.., :cover?, "2"..)
    assert_not_operator(2..., :cover?, 2..)
    assert_operator(2..., :cover?, 3...)
    assert_not_operator(2..., :cover?, 3..)
    assert_not_operator(3.., :cover?, 2..)

    assert_operator(nil..., :cover?, Object.new)
    assert_operator(nil..., :cover?, nil...)
    assert_operator(nil.., :cover?, nil...)
    assert_not_operator(nil..., :cover?, nil..)
    assert_not_operator(nil..., :cover?, 1..)
  end

  def test_beg_len
    o = Object.new
    assert_raise(TypeError) { [][o] }
    class << o; attr_accessor :begin end
    o.begin = -10
    assert_raise(TypeError) { [][o] }
    class << o; attr_accessor :end end
    o.end = 0
    assert_raise(TypeError) { [][o] }
    def o.exclude_end=(v) @exclude_end = v end
    def o.exclude_end?() @exclude_end end
    o.exclude_end = false
    assert_nil([0][o])
    assert_raise(RangeError) { [0][o] = 1 }
    class << o
      private :begin, :end
    end
    o.begin = 10
    o.end = 10
    assert_nil([0][o])
    o.begin = 0
    assert_equal([0], [0][o])
    o.begin = 2
    o.end = 0
    assert_equal([], [0, 1, 2][o])
  end

  class CyclicRange < Range
    def <=>(other); true; end
  end
  def test_cyclic_range_inspect
    o = CyclicRange.allocate
    o.instance_eval { initialize(o, 1) }
    assert_equal("(... .. ...)..1", o.inspect)
  end

  def test_comparison_when_recursive
    x = CyclicRange.allocate; x.send(:initialize, x, 1)
    y = CyclicRange.allocate; y.send(:initialize, y, 1)
    Timeout.timeout(1) {
      assert_equal x, y
      assert_operator x, :eql?, y
    }

    z = CyclicRange.allocate; z.send(:initialize, z, :another)
    Timeout.timeout(1) {
      assert_not_equal x, z
      assert_not_operator x, :eql?, z
    }

    x = CyclicRange.allocate
    y = CyclicRange.allocate
    x.send(:initialize, y, 1)
    y.send(:initialize, x, 1)
    Timeout.timeout(1) {
      assert_equal x, y
      assert_operator x, :eql?, y
    }

    x = CyclicRange.allocate
    z = CyclicRange.allocate
    x.send(:initialize, z, 1)
    z.send(:initialize, x, :other)
    Timeout.timeout(1) {
      assert_not_equal x, z
      assert_not_operator x, :eql?, z
    }
  end

  def test_size
    Enumerator.product([:to_i, :to_f, :to_r].repeated_permutation(2), [1, 10], [5, 5.5], [true, false]) do |(m1, m2), beg, ende, exclude_end|
      r = Range.new(beg.send(m1), ende.send(m2), exclude_end)
      iterable = true
      yielded = []
      begin
        r.each { yielded << _1 }
      rescue TypeError
        iterable = false
      end

      if iterable
        assert_equal(yielded.size, r.size, "failed on #{r}")
        assert_equal(yielded.size, r.each.size, "failed on #{r}")
      else
        assert_raise(TypeError, "failed on #{r}") { r.size }
        assert_raise(TypeError, "failed on #{r}") { r.each.size }
      end
    end

    assert_nil ("a"..."z").size

    assert_equal Float::INFINITY, (1..).size
    assert_raise(TypeError) { (1.0..).size }
    assert_raise(TypeError) { (1r..).size }
    assert_nil ("a"..).size

    assert_raise(TypeError) { (..1).size }
    assert_raise(TypeError) { (..1.0).size }
    assert_raise(TypeError) { (..1r).size }
    assert_raise(TypeError) { (..'z').size }

    assert_raise(TypeError) { (nil...nil).size }
  end

  def test_bsearch_typechecks_return_values
    assert_raise(TypeError) do
      (1..42).bsearch{ "not ok" }
    end
    c = eval("class C\u{309a 26a1 26c4 1f300};self;end")
    assert_raise_with_message(TypeError, /C\u{309a 26a1 26c4 1f300}/) do
      (1..42).bsearch {c.new}
    end
    assert_equal (1..42).bsearch{}, (1..42).bsearch{false}
  end

  def test_bsearch_with_no_block
    enum = (42...666).bsearch
    assert_nil enum.size
    assert_equal 200, enum.each{|x| x >= 200 }
  end

  def test_bsearch_for_other_numerics
    assert_raise(TypeError) {
      (Rational(-1,2)..Rational(9,4)).bsearch
    }
  end

  def test_bsearch_for_fixnum
    ary = [3, 4, 7, 9, 12]
    assert_equal(0, (0...ary.size).bsearch {|i| ary[i] >= 2 })
    assert_equal(1, (0...ary.size).bsearch {|i| ary[i] >= 4 })
    assert_equal(2, (0...ary.size).bsearch {|i| ary[i] >= 6 })
    assert_equal(3, (0...ary.size).bsearch {|i| ary[i] >= 8 })
    assert_equal(4, (0...ary.size).bsearch {|i| ary[i] >= 10 })
    assert_equal(nil, (0...ary.size).bsearch {|i| ary[i] >= 100 })
    assert_equal(0, (0...ary.size).bsearch {|i| true })
    assert_equal(nil, (0...ary.size).bsearch {|i| false })

    ary = [0, 100, 100, 100, 200]
    assert_equal(1, (0...ary.size).bsearch {|i| ary[i] >= 100 })

    assert_equal(1_000_001, (0...).bsearch {|i| i > 1_000_000 })
    assert_equal( -999_999, (...0).bsearch {|i| i > -1_000_000 })
  end

  def test_bsearch_for_float
    inf = Float::INFINITY
    assert_in_delta(10.0, (0.0...100.0).bsearch {|x| x > 0 && Math.log(x / 10) >= 0 }, 0.0001)
    assert_in_delta(10.0, (0.0...inf).bsearch {|x| x > 0 && Math.log(x / 10) >= 0 }, 0.0001)
    assert_in_delta(-10.0, (-inf..100.0).bsearch {|x| x >= 0 || Math.log(-x / 10) < 0 }, 0.0001)
    assert_in_delta(10.0, (-inf..inf).bsearch {|x| x > 0 && Math.log(x / 10) >= 0 }, 0.0001)
    assert_equal(nil, (-inf..5).bsearch {|x| x > 0 && Math.log(x / 10) >= 0 }, 0.0001)

    assert_in_delta(10.0, (-inf.. 10).bsearch {|x| x > 0 && Math.log(x / 10) >= 0 }, 0.0001)
    assert_equal(nil,     (-inf...10).bsearch {|x| x > 0 && Math.log(x / 10) >= 0 }, 0.0001)

    assert_equal(nil, (-inf..inf).bsearch { false })
    assert_equal(-inf, (-inf..inf).bsearch { true })

    assert_equal(inf, (0..inf).bsearch {|x| x == inf })
    assert_equal(nil, (0...inf).bsearch {|x| x == inf })

    v = (-inf..0).bsearch {|x| x != -inf }
    assert_operator(-Float::MAX, :>=, v)
    assert_operator(-inf, :<, v)

    v = (0.0..1.0).bsearch {|x| x > 0 } # the nearest positive value to 0.0
    assert_in_delta(0, v, 0.0001)
    assert_operator(0, :<, v)
    assert_equal(0.0, (-1.0..0.0).bsearch {|x| x >= 0 })
    assert_equal(nil, (-1.0...0.0).bsearch {|x| x >= 0 })

    v = (0..Float::MAX).bsearch {|x| x >= Float::MAX }
    assert_in_delta(Float::MAX, v)
    assert_equal(nil, v.infinite?)

    v = (0..inf).bsearch {|x| x >= Float::MAX }
    assert_in_delta(Float::MAX, v)
    assert_equal(nil, v.infinite?)

    v = (-Float::MAX..0).bsearch {|x| x > -Float::MAX }
    assert_operator(-Float::MAX, :<, v)
    assert_equal(nil, v.infinite?)

    v = (-inf..0).bsearch {|x| x >= -Float::MAX }
    assert_in_delta(-Float::MAX, v)
    assert_equal(nil, v.infinite?)

    v = (-inf..0).bsearch {|x| x > -Float::MAX }
    assert_operator(-Float::MAX, :<, v)
    assert_equal(nil, v.infinite?)

    assert_in_delta(1.0, (0.0..inf).bsearch {|x| Math.log(x) >= 0 })
    assert_in_delta(7.0, (0.0..10).bsearch {|x| 7.0 - x })

    assert_equal( 1_000_000.0.next_float, (0.0..).bsearch {|x| x > 1_000_000 })
    assert_equal(-1_000_000.0.next_float, (..0.0).bsearch {|x| x > -1_000_000 })
  end

  def check_bsearch_values(range, search, a)
    from, to = range.begin, range.end
    cmp = range.exclude_end? ? :< : :<=
    r = nil

    a.for "(0) trivial test" do
      r = Range.new(to, from, range.exclude_end?).bsearch do |x|
        fail "#{to}, #{from}, #{range.exclude_end?}, #{x}"
      end
      assert_nil r

      r = (to...to).bsearch do
        fail
      end
      assert_nil r
    end

    # prepare for others
    yielded = []
    r = range.bsearch do |val|
      yielded << val
      val >= search
    end

    a.for "(1) log test" do
      max = case from
            when Float then 65
            when Integer then Math.log(to-from+(range.exclude_end? ? 0 : 1), 2).to_i + 1
            end
      assert_operator yielded.size, :<=, max
    end

    a.for "(2) coverage test" do
      expect = case
               when search < from
                 from
               when search.send(cmp, to)
                 search
               else
                 nil
               end
      assert_equal expect, r
    end

    a.for "(3) uniqueness test" do
      assert_nil yielded.uniq!
    end

    a.for "(4) end of range test" do
      case
      when range.exclude_end?
        assert_not_include yielded, to
        assert_not_equal r, to
      when search >= to
        assert_include yielded, to
        assert_equal search == to ? to : nil, r
      end
    end

    a.for "(5) start of range test" do
      if search <= from
        assert_include yielded, from
        assert_equal from, r
      end
    end

    a.for "(6) out of range test" do
      yielded.each do |val|
        assert_operator from, :<=, val
        assert_send [val, cmp, to]
      end
    end
  end

  def test_range_bsearch_for_floats
    ints   = [-1 << 100, -123456789, -42, -1, 0, 1, 42, 123456789, 1 << 100]
    floats = [-Float::INFINITY, -Float::MAX, -42.0, -4.2, -Float::EPSILON, -Float::MIN, 0.0, Float::MIN, Float::EPSILON, Math::PI, 4.2, 42.0, Float::MAX, Float::INFINITY]

    all_assertions do |a|
      [ints, floats].each do |values|
        values.combination(2).to_a.product(values).each do |(from, to), search|
          check_bsearch_values(from..to, search, a)
          check_bsearch_values(from...to, search, a)
        end
      end
    end
  end

  def test_bsearch_for_bignum
    bignum = 2**100
    ary = [3, 4, 7, 9, 12]
    assert_equal(bignum + 0, (bignum...bignum+ary.size).bsearch {|i| ary[i - bignum] >= 2 })
    assert_equal(bignum + 1, (bignum...bignum+ary.size).bsearch {|i| ary[i - bignum] >= 4 })
    assert_equal(bignum + 2, (bignum...bignum+ary.size).bsearch {|i| ary[i - bignum] >= 6 })
    assert_equal(bignum + 3, (bignum...bignum+ary.size).bsearch {|i| ary[i - bignum] >= 8 })
    assert_equal(bignum + 4, (bignum...bignum+ary.size).bsearch {|i| ary[i - bignum] >= 10 })
    assert_equal(nil, (bignum...bignum+ary.size).bsearch {|i| ary[i - bignum] >= 100 })
    assert_equal(bignum + 0, (bignum...bignum+ary.size).bsearch {|i| true })
    assert_equal(nil, (bignum...bignum+ary.size).bsearch {|i| false })

    assert_equal(bignum * 2 + 1, (0...).bsearch {|i| i > bignum * 2 })
    assert_equal(bignum * 2 + 1, (bignum...).bsearch {|i| i > bignum * 2 })
    assert_equal(-bignum * 2 + 1, (...0).bsearch {|i| i > -bignum * 2 })
    assert_equal(-bignum * 2 + 1, (...-bignum).bsearch {|i| i > -bignum * 2 })

    assert_raise(TypeError) { ("a".."z").bsearch {} }
  end

  def test_each_no_blockarg
    a = "a"
    def a.upto(x, e, &b)
      super {|y| b.call(y) {|z| assert(false)}}
    end
    (a.."c").each {|x, &b| assert_nil(b)}
  end

  def test_to_a
    assert_equal([1,2,3,4,5], (1..5).to_a)
    assert_equal([1,2,3,4], (1...5).to_a)
    assert_raise(RangeError) { (1..).to_a }
  end

  def test_beginless_range_iteration
    assert_raise(TypeError) { (..1).each { } }
  end

  def test_count
    assert_equal 42, (1..42).count
    assert_equal 41, (1...42).count
    assert_equal 0, (42..1).count
    assert_equal 0, (42...1).count
    assert_equal 2**100, (1..2**100).count
    assert_equal 6, (1...6.3).count
    assert_equal 4, ('a'..'d').count
    assert_equal 3, ('a'...'d').count

    assert_equal(Float::INFINITY, (1..).count)
    assert_equal(Float::INFINITY, (..1).count)
  end

  def test_overlap?
    assert_not_operator(0..2, :overlap?, -2..-1)
    assert_not_operator(0..2, :overlap?, -2...0)
    assert_operator(0..2, :overlap?, -1..0)
    assert_operator(0..2, :overlap?, 1..2)
    assert_operator(0..2, :overlap?, 2..3)
    assert_not_operator(0..2, :overlap?, 3..4)
    assert_not_operator(0...2, :overlap?, 2..3)

    assert_operator(..0, :overlap?, -1..0)
    assert_operator(...0, :overlap?, -1..0)
    assert_operator(..0, :overlap?, 0..1)
    assert_operator(..0, :overlap?, ..1)
    assert_not_operator(..0, :overlap?, 1..2)
    assert_not_operator(...0, :overlap?, 0..1)

    assert_not_operator(0.., :overlap?, -2..-1)
    assert_not_operator(0.., :overlap?, ...0)
    assert_operator(0.., :overlap?, -1..0)
    assert_operator(0.., :overlap?, ..0)
    assert_operator(0.., :overlap?, 0..1)
    assert_operator(0.., :overlap?, 1..2)
    assert_operator(0.., :overlap?, 1..)

    assert_not_operator((1..3), :overlap?, ('a'..'d'))
    assert_not_operator((1..), :overlap?, ('a'..))
    assert_not_operator((..1), :overlap?, (..'a'))

    assert_raise(TypeError) { (0..).overlap?(1) }
    assert_raise(TypeError) { (0..).overlap?(nil) }

    assert_operator((1..3), :overlap?, (2..4))
    assert_operator((1...3), :overlap?, (2..3))
    assert_operator((2..3), :overlap?, (1..2))
    assert_operator((..3), :overlap?, (3..))
    assert_operator((nil..nil), :overlap?, (3..))
    assert_operator((nil...nil), :overlap?, (nil..))
    assert_operator((nil..nil), :overlap?, (..3))

    assert_raise(TypeError) { (1..3).overlap?(1) }

    assert_not_operator((1..2), :overlap?, (2...2))
    assert_not_operator((2...2), :overlap?, (1..2))

    assert_not_operator((4..1), :overlap?, (2..3))
    assert_not_operator((4..1), :overlap?, (..3))
    assert_not_operator((4..1), :overlap?, (2..))

    assert_not_operator((1..4), :overlap?, (3..2))
    assert_not_operator((..4), :overlap?, (3..2))
    assert_not_operator((1..), :overlap?, (3..2))

    assert_not_operator((4..5), :overlap?, (2..3))
    assert_not_operator((4..5), :overlap?, (2...4))

    assert_not_operator((1..2), :overlap?, (3..4))
    assert_not_operator((1...3), :overlap?, (3..4))

    assert_not_operator((4..5), :overlap?, (2..3))
    assert_not_operator((4..5), :overlap?, (2...4))

    assert_not_operator((1..2), :overlap?, (3..4))
    assert_not_operator((1...3), :overlap?, (3..4))
    assert_not_operator((...3), :overlap?, (3..))
  end
end
