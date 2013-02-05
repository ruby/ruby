require 'test/unit'
require 'delegate'
require 'timeout'
require 'bigdecimal'
require_relative 'envutil'

class TestRange < Test::Unit::TestCase
  def test_range_string
    # XXX: Is this really the test of Range?
    assert_equal([], ("a" ... "a").to_a)
    assert_equal(["a"], ("a" .. "a").to_a)
    assert_equal(["a"], ("a" ... "b").to_a)
    assert_equal(["a", "b"], ("a" .. "b").to_a)
  end

  def test_range_numeric_string
    assert_equal(["6", "7", "8"], ("6".."8").to_a, "[ruby-talk:343187]")
    assert_equal(["6", "7"], ("6"..."8").to_a)
    assert_equal(["9", "10"], ("9".."10").to_a)
    assert_equal(["09", "10"], ("09".."10").to_a, "[ruby-dev:39361]")
    assert_equal(["9", "10"], (SimpleDelegator.new("9").."10").to_a)
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

    assert_equal(1.0, (1.0..2.0).min)
    assert_equal(nil, (2.0..1.0).min)
    assert_equal(1, (1.0...2.0).min)

    assert_equal(0, (0..0).min)
    assert_equal(nil, (0...0).min)
  end

  def test_max
    assert_equal(2, (1..2).max)
    assert_equal(nil, (2..1).max)
    assert_equal(1, (1...2).max)

    assert_equal(2.0, (1.0..2.0).max)
    assert_equal(nil, (2.0..1.0).max)
    assert_raise(TypeError) { (1.0...2.0).max }
    assert_raise(TypeError) { (1...1.5).max }
    assert_raise(TypeError) { (1.5...2).max }

    assert_equal(-0x80000002, ((-0x80000002)...(-0x80000001)).max)

    assert_equal(0, (0..0).max)
    assert_equal(nil, (0...0).max)
  end

  def test_initialize_twice
    r = eval("1..2")
    assert_raise(NameError) { r.instance_eval { initialize 3, 4 } }
  end

  def test_uninitialized_range
    r = Range.allocate
    s = Marshal.dump(r)
    r = Marshal.load(s)
    assert_nothing_raised { r.instance_eval { initialize 5, 6} }
  end

  def test_bad_value
    assert_raise(ArgumentError) { (1 .. :a) }
  end

  def test_exclude_end
    assert(!((0..1).exclude_end?))
    assert((0...1).exclude_end?)
  end

  def test_eq
    r = (0..1)
    assert(r == r)
    assert(r == (0..1))
    assert(r != 0)
    assert(r != (1..2))
    assert(r != (0..2))
    assert(r != (0...1))
    subclass = Class.new(Range)
    assert(r == subclass.new(0,1))
  end

  def test_eql
    r = (0..1)
    assert(r.eql?(r))
    assert(r.eql?(0..1))
    assert(!r.eql?(0))
    assert(!r.eql?(1..2))
    assert(!r.eql?(0..2))
    assert(!r.eql?(0...1))
    subclass = Class.new(Range)
    assert(r.eql?(subclass.new(0,1)))
  end

  def test_hash
    assert((0..1).hash.is_a?(Fixnum))
  end

  def test_step
    a = []
    (0..10).step {|x| a << x }
    assert_equal([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], a)

    a = []
    (0..10).step(2) {|x| a << x }
    assert_equal([0, 2, 4, 6, 8, 10], a)

    assert_raise(ArgumentError) { (0..10).step(-1) { } }
    assert_raise(ArgumentError) { (0..10).step(0) { } }

    a = []
    ("a" .. "z").step(2) {|x| a << x }
    assert_equal(%w(a c e g i k m o q s u w y), a)

    a = []
    ("a" .. "z").step(2**32) {|x| a << x }
    assert_equal(["a"], a)

    a = []
    (2**32-1 .. 2**32+1).step(2) {|x| a << x }
    assert_equal([4294967295, 4294967297], a)
    zero = (2**32).coerce(0).first
    assert_raise(ArgumentError) { (2**32-1 .. 2**32+1).step(zero) { } }

    o1 = Object.new
    o2 = Object.new
    def o1.<=>(x); -1; end
    def o2.<=>(x); 0; end
    assert_raise(TypeError) { (o1..o2).step(1) { } }

    class << o1; self; end.class_eval do
      define_method(:succ) { o2 }
    end
    a = []
    (o1..o2).step(1) {|x| a << x }
    assert_equal([o1, o2], a)

    a = []
    (o1...o2).step(1) {|x| a << x }
    assert_equal([o1], a)

    assert_nothing_raised("[ruby-dev:34557]") { (0..2).step(0.5) {|x| } }

    a = []
    (0..2).step(0.5) {|x| a << x }
    assert_equal([0, 0.5, 1.0, 1.5, 2.0], a)

    a = []
    (0x40000000..0x40000002).step(0.5) {|x| a << x }
    assert_equal([1073741824, 1073741824.5, 1073741825.0, 1073741825.5, 1073741826], a)

    o = Object.new
    def o.to_int() 1 end
    assert_nothing_raised("[ruby-dev:34558]") { (0..2).step(o) {|x| } }
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
  end

  def test_begin_end
    assert_equal(0, (0..1).begin)
    assert_equal(1, (0..1).end)
  end

  def test_first_last
    assert_equal([0, 1, 2], (0..10).first(3))
    assert_equal([8, 9, 10], (0..10).last(3))
  end

  def test_to_s
    assert_equal("0..1", (0..1).to_s)
    assert_equal("0...1", (0...1).to_s)
  end

  def test_inspect
    assert_equal("0..1", (0..1).inspect)
    assert_equal("0...1", (0...1).inspect)
  end

  def test_eqq
    assert((0..10) === 5)
    assert(!((0..10) === 11))
  end

  def test_include
    assert(("a".."z").include?("c"))
    assert(!(("a".."z").include?("5")))
    assert(("a"..."z").include?("y"))
    assert(!(("a"..."z").include?("z")))
    assert(!(("a".."z").include?("cc")))
    assert((0...10).include?(5))
  end

  def test_cover
    assert(("a".."z").cover?("c"))
    assert(!(("a".."z").cover?("5")))
    assert(("a"..."z").cover?("y"))
    assert(!(("a"..."z").cover?("z")))
    assert(("a".."z").cover?("cc"))
  end

  def test_beg_len
    o = Object.new
    assert_raise(TypeError) { [][o] }
    class << o; attr_accessor :begin end
    o.begin = -10
    assert_raise(TypeError) { [][o] }
    class << o; attr_accessor :end end
    o.end = 0
    assert_raise(NoMethodError) { [][o] }
    def o.exclude_end=(v) @exclude_end = v end
    def o.exclude_end?() @exclude_end end
    o.exclude_end = false
    assert_nil([0][o])
    assert_raise(RangeError) { [0][o] = 1 }
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
      assert x == y
      assert x.eql? y
    }

    z = CyclicRange.allocate; z.send(:initialize, z, :another)
    Timeout.timeout(1) {
      assert x != z
      assert !x.eql?(z)
    }

    x = CyclicRange.allocate
    y = CyclicRange.allocate
    x.send(:initialize, y, 1)
    y.send(:initialize, x, 1)
    Timeout.timeout(1) {
      assert x == y
      assert x.eql?(y)
    }

    x = CyclicRange.allocate
    z = CyclicRange.allocate
    x.send(:initialize, z, 1)
    z.send(:initialize, x, :other)
    Timeout.timeout(1) {
      assert x != z
      assert !x.eql?(z)
    }
  end

  def test_size
    assert_equal 42, (1..42).size
    assert_equal 41, (1...42).size
    assert_equal 6, (1...6.3).size
    assert_equal 5, (1.1...6).size
    assert_equal 42, (1..42).each.size
  end

  def test_bsearch_typechecks_return_values
    assert_raise(TypeError) do
      (1..42).bsearch{ "not ok" }
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
    assert_raise(TypeError) {
      (BigDecimal('0.5')..BigDecimal('2.25')).bsearch
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
  end

  def check_bsearch_values(range, search)
    from, to = range.begin, range.end
    cmp = range.exclude_end? ? :< : :<=

    # (0) trivial test
    r = Range.new(to, from, range.exclude_end?).bsearch do |x|
      fail "#{to}, #{from}, #{range.exclude_end?}, #{x}"
    end
    assert_equal nil, r

    r = (to...to).bsearch do
      fail
    end
    assert_equal nil, r

    # prepare for others
    yielded = []
    r = range.bsearch do |val|
      yielded << val
      val >= search
    end

    # (1) log test
    max = case from
          when Float then 65
          when Integer then Math.log(to-from+(range.exclude_end? ? 0 : 1), 2).to_i + 1
          end
    assert yielded.size <= max

    # (2) coverage test
    expect =  if search < from
                from
              elsif search.send(cmp, to)
                search
              else
                nil
              end
    assert_equal expect, r

    # (3) uniqueness test
    assert_equal nil, yielded.uniq!

    # (4) end of range test
    case
    when range.exclude_end?
      assert !yielded.include?(to)
      assert r != to
    when search >= to
      assert yielded.include?(to)
      assert_equal search == to ? to : nil, r
    end

    # start of range test
    if search <= from
      assert yielded.include?(from)
      assert_equal from, r
    end

    # (5) out of range test
    yielded.each do |val|
      assert from <= val && val.send(cmp, to)
    end
  end

  def test_range_bsearch_for_floats
    ints   = [-1 << 100, -123456789, -42, -1, 0, 1, 42, 123456789, 1 << 100]
    floats = [-Float::INFINITY, -Float::MAX, -42.0, -4.2, -Float::EPSILON, -Float::MIN, 0.0, Float::MIN, Float::EPSILON, Math::PI, 4.2, 42.0, Float::MAX, Float::INFINITY]

    [ints, floats].each do |values|
      values.combination(2).to_a.product(values).each do |(from, to), search|
        check_bsearch_values(from..to, search)
        check_bsearch_values(from...to, search)
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

    assert_raise(TypeError) { ("a".."z").bsearch {} }
  end

  def test_bsearch_with_mathn
    assert_separately ['-r', 'mathn'], %q{
      msg = '[ruby-core:25740]'
      answer = (1..(1 << 100)).bsearch{|x|
        assert_predicate(x, :integer?, msg)
        x >= 42
      }
      assert_equal(42, answer, msg)
    }
  end
end
