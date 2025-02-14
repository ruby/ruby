# frozen_string_literal: false
require 'test/unit'

class TestAssignment < Test::Unit::TestCase
  def test_assign
    a=[]; a[0] ||= "bar";
    assert_equal("bar", a[0])
    h={}; h["foo"] ||= "bar";
    assert_equal("bar", h["foo"])

    aa = 5
    aa ||= 25
    assert_equal(5, aa)
    bb ||= 25
    assert_equal(25, bb)
    cc &&=33
    assert_nil(cc)
    cc = 5
    cc &&=44
    assert_equal(44, cc)
  end

  def test_assign_simple
    a = nil; assert_nil(a)
    a = 1; assert_equal(1, a)
    a = []; assert_equal([], a)
    a = [1]; assert_equal([1], a)
    a = [nil]; assert_equal([nil], a)
    a = [[]]; assert_equal([[]], a)
    a = [1,2]; assert_equal([1,2], a)
    a = [*[]]; assert_equal([], a)
    a = [*[1]]; assert_equal([1], a)
    a = [*[1,2]]; assert_equal([1,2], a)
  end

  def test_assign_splat
    a = *[]; assert_equal([], a)
    a = *[1]; assert_equal([1], a)
    a = *[nil]; assert_equal([nil], a)
    a = *[[]]; assert_equal([[]], a)
    a = *[1,2]; assert_equal([1,2], a)
    a = *[*[]]; assert_equal([], a)
    a = *[*[1]]; assert_equal([1], a)
    a = *[*[1,2]]; assert_equal([1,2], a)
  end

  def test_assign_ary
    *a = nil; assert_equal([nil], a)
    *a = 1; assert_equal([1], a)
    *a = []; assert_equal([], a)
    *a = [1]; assert_equal([1], a)
    *a = [nil]; assert_equal([nil], a)
    *a = [[]]; assert_equal([[]], a)
    *a = [1,2]; assert_equal([1,2], a)
    *a = [*[]]; assert_equal([], a)
    *a = [*[1]]; assert_equal([1], a)
    *a = [*[1,2]]; assert_equal([1,2], a)
  end

  def test_assign_ary_splat
    *a = *[]; assert_equal([], a)
    *a = *[1]; assert_equal([1], a)
    *a = *[nil]; assert_equal([nil], a)
    *a = *[[]]; assert_equal([[]], a)
    *a = *[1,2]; assert_equal([1,2], a)
    *a = *[*[]]; assert_equal([], a)
    *a = *[*[1]]; assert_equal([1], a)
    *a = *[*[1,2]]; assert_equal([1,2], a)
  end

  def test_massign_simple
    a,b,*c = nil; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = 1; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = []; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = [1]; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = [nil]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = [[]]; assert_equal([[],nil,[]], [a,b,c])
    a,b,*c = [1,2]; assert_equal([1,2,[]], [a,b,c])
    a,b,*c = [*[]]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = [*[1]]; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = [*[1,2]]; assert_equal([1,2,[]], [a,b,c])
  end

  def test_massign_order
    order = []
    define_singleton_method(:x1){order << :x1; self}
    define_singleton_method(:y1){order << :y1; self}
    define_singleton_method(:z=){|x| order << [:z=, x]}
    define_singleton_method(:x2){order << :x2; self}
    define_singleton_method(:x3){order << :x3; self}
    define_singleton_method(:x4){order << :x4; self}
    define_singleton_method(:x5=){|x| order << [:x5=, x]; self}
    define_singleton_method(:[]=){|*args| order << [:[]=, *args]}
    define_singleton_method(:r1){order << :r1; :r1}
    define_singleton_method(:r2){order << :r2; :r2}

    x1.y1.z, x2[1, 2, 3], self[4] = r1, 6, r2
    assert_equal([:x1, :y1, :x2, :r1, :r2, [:z=, :r1], [:[]=, 1, 2, 3, 6], [:[]=, 4, :r2]], order)
    order.clear

    x1.y1.z, *x2[1, 2, 3], self[4] = r1, 6, 7, r2
    assert_equal([:x1, :y1, :x2, :r1, :r2, [:z=, :r1], [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, :r2]], order)
    order.clear

    x1.y1.z, *x2[1, 2, 3], x3[4] = r1, 6, 7, r2
    assert_equal([:x1, :y1, :x2, :x3, :r1, :r2, [:z=, :r1], [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, :r2]], order)
    order.clear

    x1.y1.z, *x2[1, 2, 3], x3[4], x4.x5 = r1, 6, 7, r2, 8
    assert_equal([:x1, :y1, :x2, :x3, :x4, :r1, :r2, [:z=, :r1], [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, :r2], [:x5=, 8]], order)
    order.clear

    (x1.y1.z, x2.x5), _a = [r1, r2], 7
    assert_equal([:x1, :y1, :x2, :r1, :r2, [:z=, :r1], [:x5=, :r2]], order)
    order.clear

    (x1.y1.z, x1.x5), *x2[1, 2, 3] = [r1, 5], 6, 7, r2, 8
    assert_equal([:x1, :y1, :x1, :x2, :r1, :r2, [:z=, :r1], [:x5=, 5], [:[]=, 1, 2, 3, [6, 7, :r2, 8]]], order)
    order.clear

    *x2[1, 2, 3], (x3[4], x4.x5) = 6, 7, [r2, 8]
    assert_equal([:x2, :x3, :x4, :r2, [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, :r2], [:x5=, 8]], order)
    order.clear

    (x1.y1.z, x1.x5), *x2[1, 2, 3], x3[4], x4.x5 = [r1, 5], 6, 7, r2, 8
    assert_equal([:x1, :y1, :x1, :x2, :x3, :x4, :r1, :r2, [:z=, :r1], [:x5=, 5], [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, :r2], [:x5=, 8]], order)
    order.clear

    (x1.y1.z, x1.x5), *x2[1, 2, 3], (x3[4], x4.x5) = [r1, 5], 6, 7, [r2, 8]
    assert_equal([:x1, :y1, :x1, :x2, :x3, :x4, :r1, :r2, [:z=, :r1], [:x5=, 5], [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, :r2], [:x5=, 8]], order)
    order.clear

    ((x1.y1.z, x1.x5), _a), *x2[1, 2, 3], ((x3[4], x4.x5), _b) = [[r1, 5], 10], 6, 7, [[r2, 8], 11]
    assert_equal([:x1, :y1, :x1, :x2, :x3, :x4, :r1, :r2, [:z=, :r1], [:x5=, 5], [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, :r2], [:x5=, 8]], order)
    order.clear

    ((x1.y1.z, *x1.x5), _a), *x2[1, 2, 3], ((*x3[4], x4.x5), _b) = [[r1, 5], 10], 6, 7, [[r2, 8], 11]
    assert_equal([:x1, :y1, :x1, :x2, :x3, :x4, :r1, :r2, [:z=, :r1], [:x5=, [5]], [:[]=, 1, 2, 3, [6, 7]], [:[]=, 4, [:r2]], [:x5=, 8]], order)
    order.clear
  end

  def test_massign_const_order
    order = []

    test_mod_class = Class.new(Module) do
      define_method(:x1){order << :x1; self}
      define_method(:y1){order << :y1; self}
      define_method(:x2){order << :x2; self}
      define_method(:x3){order << :x3; self}
      define_method(:x4){order << :x4; self}
      define_method(:[]){|*args| order << [:[], *args]; self}
      define_method(:r1){order << :r1; :r1}
      define_method(:r2){order << :r2; :r2}

      define_method(:constant_values) do
        h = {}
        constants.each do |sym|
          h[sym] = const_get(sym)
        end
        h
      end

      define_singleton_method(:run) do |code|
        m = new
        m.instance_eval(code)
        ret = [order.dup, m.constant_values]
        order.clear
        ret
      end
    end

    ord, constants = test_mod_class.run(
      "x1.y1::A, x2[1, 2, 3]::B, self[4]::C = r1, 6, r2"
    )
    assert_equal([:x1, :y1, :x2, [:[], 1, 2, 3], [:[], 4], :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>6, :C=>:r2}, constants)

    ord, constants = test_mod_class.run(
      "x1.y1::A, *x2[1, 2, 3]::B, self[4]::C = r1, 6, 7, r2"
    )
    assert_equal([:x1, :y1, :x2, [:[], 1, 2, 3], [:[], 4], :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>[6, 7], :C=>:r2}, constants)

    ord, constants = test_mod_class.run(
      "x1.y1::A, *x2[1, 2, 3]::B, x3[4]::C = r1, 6, 7, r2"
    )
    assert_equal([:x1, :y1, :x2, [:[], 1, 2, 3], :x3, [:[], 4], :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>[6, 7], :C=>:r2}, constants)


    ord, constants = test_mod_class.run(
      "x1.y1::A, *x2[1, 2, 3]::B, x3[4]::C, x4::D = r1, 6, 7, r2, 8"
    )
    assert_equal([:x1, :y1, :x2, [:[], 1, 2, 3], :x3, [:[], 4], :x4, :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>[6, 7], :C=>:r2, :D=>8}, constants)

    ord, constants = test_mod_class.run(
      "(x1.y1::A, x2::B), _a = [r1, r2], 7"
    )
    assert_equal([:x1, :y1, :x2, :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>:r2}, constants)

    ord, constants = test_mod_class.run(
      "(x1.y1::A, x1::B), *x2[1, 2, 3]::C = [r1, 5], 6, 7, r2, 8"
    )
    assert_equal([:x1, :y1, :x1, :x2, [:[], 1, 2, 3], :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>5, :C=>[6, 7, :r2, 8]}, constants)

    ord, constants = test_mod_class.run(
      "*x2[1, 2, 3]::A, (x3[4]::B, x4::C) = 6, 7, [r2, 8]"
    )
    assert_equal([:x2, [:[], 1, 2, 3], :x3, [:[], 4], :x4, :r2], ord)
    assert_equal({:A=>[6, 7], :B=>:r2, :C=>8}, constants)

    ord, constants = test_mod_class.run(
      "(x1.y1::A, x1::B), *x2[1, 2, 3]::C, x3[4]::D, x4::E = [r1, 5], 6, 7, r2, 8"
    )
    assert_equal([:x1, :y1, :x1, :x2, [:[], 1, 2, 3], :x3, [:[], 4], :x4, :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>5, :C=>[6, 7], :D=>:r2, :E=>8}, constants)

    ord, constants = test_mod_class.run(
      "(x1.y1::A, x1::B), *x2[1, 2, 3]::C, (x3[4]::D, x4::E) = [r1, 5], 6, 7, [r2, 8]"
    )
    assert_equal([:x1, :y1, :x1, :x2, [:[], 1, 2, 3], :x3, [:[], 4], :x4, :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>5, :C=>[6, 7], :D=>:r2, :E=>8}, constants)

    ord, constants = test_mod_class.run(
      "((x1.y1::A, x1::B), _a), *x2[1, 2, 3]::C, ((x3[4]::D, x4::E), _b) = [[r1, 5], 10], 6, 7, [[r2, 8], 11]"
    )
    assert_equal([:x1, :y1, :x1, :x2, [:[], 1, 2, 3], :x3, [:[], 4], :x4, :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>5, :C=>[6, 7], :D=>:r2, :E=>8}, constants)

    ord, constants = test_mod_class.run(
      "((x1.y1::A, x1::B), _a), *x2[1, 2, 3]::C, ((*x3[4]::D, x4::E), _b) = [[r1, 5], 10], 6, 7, [[r2, 8], 11]"
    )
    assert_equal([:x1, :y1, :x1, :x2, [:[], 1, 2, 3], :x3, [:[], 4], :x4, :r1, :r2], ord)
    assert_equal({:A=>:r1, :B=>5, :C=>[6, 7], :D=>[:r2], :E=>8}, constants)
  end

  def test_massign_splat
    a,b,*c = *[]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = *[1]; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = *[nil]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = *[[]]; assert_equal([[],nil,[]], [a,b,c])
    a,b,*c = *[1,2]; assert_equal([1,2,[]], [a,b,c])
    a,b,*c = *[*[]]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = *[*[1]]; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = *[*[1,2]]; assert_equal([1,2,[]], [a,b,c])
  end

  def test_massign_optimized_literal_bug_21012
    a = []
    def a.[]=(*args)
      push args
    end
    a["a", "b"], = 1
    a["a", 10], = 2
    assert_equal [["a", "b", 1], ["a", 10, 2]], a
  end

  def test_assign_rescue
    a = raise rescue 2; assert_equal(2, a)
    a, b = raise rescue [3,4]; assert_equal([3, 4], [a, b])
  end

  def test_assign_abbreviated
    bug2050 = '[ruby-core:25629]'
    a = Hash.new {[]}
    b = [1, 2]
    assert_equal([1, 2, 3], a[:x] += [*b, 3], bug2050)
    assert_equal([1, 2, 3], a[:x], bug2050)
    assert_equal([1, 2, 3, [1, 2, 3]], a[:x] <<= [*b, 3], bug2050)
    assert_equal([1, 2, 3, [1, 2, 3]], a[:x], bug2050)
  end

  def test_assign_private_self
    bug11096 = '[ruby-core:68984] [Bug #11096]'

    o = Object.new
    class << o
      private
      def foo; 42; end
      def [](i); 42; end
      def foo=(a); 42; end
      def []=(i, a); 42; end
    end

    assert_raise(NoMethodError, bug11096) {
      o.instance_eval {o.foo = 1}
    }
    assert_nothing_raised(NoMethodError, bug11096) {
      assert_equal(1, o.instance_eval {self.foo = 1})
    }

    assert_raise(NoMethodError, bug11096) {
      o.instance_eval {o[0] = 1}
    }
    assert_nothing_raised(NoMethodError, bug11096) {
      assert_equal(1, o.instance_eval {self[0] = 1})
    }

    assert_nothing_raised(NoMethodError, bug11096) {
      o.instance_eval {self.foo += 1}
    }
    assert_nothing_raised(NoMethodError, bug11096) {
      o.instance_eval {self.foo &&= 1}
    }

    assert_nothing_raised(NoMethodError, bug11096) {
      o.instance_eval {self[0] += 1}
    }
    assert_nothing_raised(NoMethodError, bug11096) {
      o.instance_eval {self[0] &&= 1}
    }
  end

  def test_yield
    def f; yield(nil); end; f {|a| assert_nil(a)}; undef f
    def f; yield(1); end; f {|a| assert_equal(1, a)}; undef f
    def f; yield([]); end; f {|a| assert_equal([], a)}; undef f
    def f; yield([1]); end; f {|a| assert_equal([1], a)}; undef f
    def f; yield([nil]); end; f {|a| assert_equal([nil], a)}; undef f
    def f; yield([[]]); end; f {|a| assert_equal([[]], a)}; undef f
    def f; yield([*[]]); end; f {|a| assert_equal([], a)}; undef f
    def f; yield([*[1]]); end; f {|a| assert_equal([1], a)}; undef f
    def f; yield([*[1,2]]); end; f {|a| assert_equal([1,2], a)}; undef f

    def f; yield(*[1]); end; f {|a| assert_equal(1, a)}; undef f
    def f; yield(*[nil]); end; f {|a| assert_equal(nil, a)}; undef f
    def f; yield(*[[]]); end; f {|a| assert_equal([], a)}; undef f
    def f; yield(*[*[1]]); end; f {|a| assert_equal(1, a)}; undef f

    def f; yield; end; f {|*a| assert_equal([], a)}; undef f
    def f; yield(nil); end; f {|*a| assert_equal([nil], a)}; undef f
    def f; yield(1); end; f {|*a| assert_equal([1], a)}; undef f
    def f; yield([]); end; f {|*a| assert_equal([[]], a)}; undef f
    def f; yield([1]); end; f {|*a| assert_equal([[1]], a)}; undef f
    def f; yield([nil]); end; f {|*a| assert_equal([[nil]], a)}; undef f
    def f; yield([[]]); end; f {|*a| assert_equal([[[]]], a)}; undef f
    def f; yield([1,2]); end; f {|*a| assert_equal([[1,2]], a)}; undef f
    def f; yield([*[]]); end; f {|*a| assert_equal([[]], a)}; undef f
    def f; yield([*[1]]); end; f {|*a| assert_equal([[1]], a)}; undef f
    def f; yield([*[1,2]]); end; f {|*a| assert_equal([[1,2]], a)}; undef f

    def f; yield(*[]); end; f {|*a| assert_equal([], a)}; undef f
    def f; yield(*[1]); end; f {|*a| assert_equal([1], a)}; undef f
    def f; yield(*[nil]); end; f {|*a| assert_equal([nil], a)}; undef f
    def f; yield(*[[]]); end; f {|*a| assert_equal([[]], a)}; undef f
    def f; yield(*[*[]]); end; f {|*a| assert_equal([], a)}; undef f
    def f; yield(*[*[1]]); end; f {|*a| assert_equal([1], a)}; undef f
    def f; yield(*[*[1,2]]); end; f {|*a| assert_equal([1,2], a)}; undef f

    def f; yield; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield(nil); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield(1); end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}; undef f
    def f; yield([]); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield([1]); end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}; undef f
    def f; yield([nil]); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield([[]]); end; f {|a,b,*c| assert_equal([[],nil,[]], [a,b,c])}; undef f
    def f; yield([*[]]); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield([*[1]]); end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}; undef f
    def f; yield([*[1,2]]); end; f {|a,b,*c| assert_equal([1,2,[]], [a,b,c])}; undef f

    def f; yield(*[]); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield(*[1]); end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}; undef f
    def f; yield(*[nil]); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield(*[[]]); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield(*[*[]]); end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}; undef f
    def f; yield(*[*[1]]); end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}; undef f
    def f; yield(*[*[1,2]]); end; f {|a,b,*c| assert_equal([1,2,[]], [a,b,c])}; undef f
  end

  def test_return
    def r; return; end; a = r(); assert_nil(a); undef r
    def r; return nil; end; a = r(); assert_nil(a); undef r
    def r; return 1; end; a = r(); assert_equal(1, a); undef r
    def r; return []; end; a = r(); assert_equal([], a); undef r
    def r; return [1]; end; a = r(); assert_equal([1], a); undef r
    def r; return [nil]; end; a = r(); assert_equal([nil], a); undef r
    def r; return [[]]; end; a = r(); assert_equal([[]], a); undef r
    def r; return [*[]]; end; a = r(); assert_equal([], a); undef r
    def r; return [*[1]]; end; a = r(); assert_equal([1], a); undef r
    def r; return [*[1,2]]; end; a = r(); assert_equal([1,2], a); undef r

    def r; return *[]; end; a = r(); assert_equal([], a); undef r
    def r; return *[1]; end; a = r(); assert_equal([1], a); undef r
    def r; return *[nil]; end; a = r(); assert_equal([nil], a); undef r
    def r; return *[[]]; end; a = r(); assert_equal([[]], a); undef r
    def r; return *[*[]]; end; a = r(); assert_equal([], a); undef r
    def r; return *[*[1]]; end; a = r(); assert_equal([1], a); undef r
    def r; return *[*[1,2]]; end; a = r(); assert_equal([1,2], a); undef r

    def r; return *[[]]; end; a = *r(); assert_equal([[]], a); undef r
    def r; return *[*[1,2]]; end; a = *r(); assert_equal([1,2], a); undef r

    def r; return; end; *a = r(); assert_equal([nil], a); undef r
    def r; return nil; end; *a = r(); assert_equal([nil], a); undef r
    def r; return 1; end; *a = r(); assert_equal([1], a); undef r
    def r; return []; end; *a = r(); assert_equal([], a); undef r
    def r; return [1]; end; *a = r(); assert_equal([1], a); undef r
    def r; return [nil]; end; *a = r(); assert_equal([nil], a); undef r
    def r; return [[]]; end; *a = r(); assert_equal([[]], a); undef r
    def r; return [1,2]; end; *a = r(); assert_equal([1,2], a); undef r
    def r; return [*[]]; end; *a = r(); assert_equal([], a); undef r
    def r; return [*[1]]; end; *a = r(); assert_equal([1], a); undef r
    def r; return [*[1,2]]; end; *a = r(); assert_equal([1,2], a); undef r

    def r; return *[]; end; *a = r(); assert_equal([], a); undef r
    def r; return *[1]; end; *a = r(); assert_equal([1], a); undef r
    def r; return *[nil]; end; *a = r(); assert_equal([nil], a); undef r
    def r; return *[[]]; end; *a = r(); assert_equal([[]], a); undef r
    def r; return *[1,2]; end; *a = r(); assert_equal([1,2], a); undef r
    def r; return *[*[]]; end; *a = r(); assert_equal([], a); undef r
    def r; return *[*[1]]; end; *a = r(); assert_equal([1], a); undef r
    def r; return *[*[1,2]]; end; *a = r(); assert_equal([1,2], a); undef r

    def r; return *[[]]; end; *a = *r(); assert_equal([[]], a); undef r
    def r; return *[1,2]; end; *a = *r(); assert_equal([1,2], a); undef r
    def r; return *[*[1,2]]; end; *a = *r(); assert_equal([1,2], a); undef r

    def r; return; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return nil; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return 1; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c]); undef r
    def r; return []; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return [1]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c]); undef r
    def r; return [nil]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return [[]]; end; a,b,*c = r(); assert_equal([[],nil,[]], [a,b,c]); undef r
    def r; return [1,2]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c]); undef r
    def r; return [*[]]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return [*[1]]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c]); undef r
    def r; return [*[1,2]]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c]); undef r

    def r; return *[]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return *[1]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c]); undef r
    def r; return *[nil]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return *[[]]; end; a,b,*c = r(); assert_equal([[],nil,[]], [a,b,c]); undef r
    def r; return *[1,2]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c]); undef r
    def r; return *[*[]]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c]); undef r
    def r; return *[*[1]]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c]); undef r
    def r; return *[*[1,2]]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c]); undef r

    def r; return 1, *[]; end; a,b = r(); assert_equal([1,nil], [a,b]); undef r
    def r; return 1,2,*[1]; end; a,b = r(); assert_equal([1,2], [a,b]); undef r
    def r; return 1,2,3,*[1,2]; end; a,b = r(); assert_equal([1,2], [a,b]); undef r
  end

  def test_lambda
    f = lambda {|r,| assert_equal([], r)}
    f.call([], *[])

    f = lambda {|r,*l| assert_equal([], r); assert_equal([1], l)}
    f.call([], *[1])

    f = lambda{|x| x}
    assert_equal(42, f.call(42))
    assert_equal([42], f.call([42]))
    assert_equal([[42]], f.call([[42]]))
    assert_equal([42,55], f.call([42,55]))

    f = lambda{|x,| x}
    assert_equal(42, f.call(42))
    assert_equal([42], f.call([42]))
    assert_equal([[42]], f.call([[42]]))
    assert_equal([42,55], f.call([42,55]))

    f = lambda{|*x| x}
    assert_equal([42], f.call(42))
    assert_equal([[42]], f.call([42]))
    assert_equal([[[42]]], f.call([[42]]))
    assert_equal([[42,55]], f.call([42,55]))
    assert_equal([42,55], f.call(42,55))
  end

  def test_multi
    a,=*[1]
    assert_equal(1, a)
    a,=*[[1]]
    assert_equal([1], a)
    a,=*[[[1]]]
    assert_equal([[1]], a)

    x, (y, z) = 1, 2, 3
    assert_equal([1,2,nil], [x,y,z])
    x, (y, z) = 1, [2,3]
    assert_equal([1,2,3], [x,y,z])
    x, (y, z) = 1, [2]
    assert_equal([1,2,nil], [x,y,z])
  end

  def test_break
    a = loop do break; end; assert_nil(a)
    a = loop do break nil; end; assert_nil(a)
    a = loop do break 1; end; assert_equal(1, a)
    a = loop do break []; end; assert_equal([], a)
    a = loop do break [1]; end; assert_equal([1], a)
    a = loop do break [nil]; end; assert_equal([nil], a)
    a = loop do break [[]]; end; assert_equal([[]], a)
    a = loop do break [*[]]; end; assert_equal([], a)
    a = loop do break [*[1]]; end; assert_equal([1], a)
    a = loop do break [*[1,2]]; end; assert_equal([1,2], a)

    a = loop do break *[]; end; assert_equal([], a)
    a = loop do break *[1]; end; assert_equal([1], a)
    a = loop do break *[nil]; end; assert_equal([nil], a)
    a = loop do break *[[]]; end; assert_equal([[]], a)
    a = loop do break *[*[]]; end; assert_equal([], a)
    a = loop do break *[*[1]]; end; assert_equal([1], a)
    a = loop do break *[*[1,2]]; end; assert_equal([1,2], a)

    *a = loop do break; end; assert_equal([nil], a)
    *a = loop do break nil; end; assert_equal([nil], a)
    *a = loop do break 1; end; assert_equal([1], a)
    *a = loop do break []; end; assert_equal([], a)
    *a = loop do break [1]; end; assert_equal([1], a)
    *a = loop do break [nil]; end; assert_equal([nil], a)
    *a = loop do break [[]]; end; assert_equal([[]], a)
    *a = loop do break [1,2]; end; assert_equal([1,2], a)
    *a = loop do break [*[]]; end; assert_equal([], a)
    *a = loop do break [*[1]]; end; assert_equal([1], a)
    *a = loop do break [*[1,2]]; end; assert_equal([1,2], a)

    *a = loop do break *[]; end; assert_equal([], a)
    *a = loop do break *[1]; end; assert_equal([1], a)
    *a = loop do break *[nil]; end; assert_equal([nil], a)
    *a = loop do break *[[]]; end; assert_equal([[]], a)
    *a = loop do break *[1,2]; end; assert_equal([1,2], a)
    *a = loop do break *[*[]]; end; assert_equal([], a)
    *a = loop do break *[*[1]]; end; assert_equal([1], a)
    *a = loop do break *[*[1,2]]; end; assert_equal([1,2], a)

    *a = *loop do break *[[]]; end; assert_equal([[]], a)
    *a = *loop do break *[1,2]; end; assert_equal([1,2], a)
    *a = *loop do break *[*[1,2]]; end; assert_equal([1,2], a)

    a,b,*c = loop do break; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break nil; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break 1; end; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = loop do break []; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break [1]; end; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = loop do break [nil]; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break [[]]; end; assert_equal([[],nil,[]], [a,b,c])
    a,b,*c = loop do break [1,2]; end; assert_equal([1,2,[]], [a,b,c])
    a,b,*c = loop do break [*[]]; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break [*[1]]; end; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = loop do break [*[1,2]]; end; assert_equal([1,2,[]], [a,b,c])

    a,b,*c = loop do break *[]; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break *[1]; end; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = loop do break *[nil]; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break *[[]]; end; assert_equal([[],nil,[]], [a,b,c])
    a,b,*c = loop do break *[1,2]; end; assert_equal([1,2,[]], [a,b,c])
    a,b,*c = loop do break *[*[]]; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break *[*[1]]; end; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = loop do break *[*[1,2]]; end; assert_equal([1,2,[]], [a,b,c])
  end

  def test_next
    def r(val); a = yield(); assert_equal(val, a); end
    r(nil){next}
    r(nil){next nil}
    r(1){next 1}
    r([]){next []}
    r([1]){next [1]}
    r([nil]){next [nil]}
    r([[]]){next [[]]}
    r([]){next [*[]]}
    r([1]){next [*[1]]}
    r([1,2]){next [*[1,2]]}

    r([]){next *[]}
    r([1]){next *[1]}
    r([nil]){next *[nil]}
    r([[]]){next *[[]]}
    r([]){next *[*[]]}
    r([1]){next *[*[1]]}
    r([1,2]){next *[*[1,2]]}
    undef r

    def r(val); *a = yield(); assert_equal(val, a); end
    r([nil]){next}
    r([nil]){next nil}
    r([1]){next 1}
    r([]){next []}
    r([1]){next [1]}
    r([nil]){next [nil]}
    r([[]]){next [[]]}
    r([1,2]){next [1,2]}
    r([]){next [*[]]}
    r([1]){next [*[1]]}
    r([1,2]){next [*[1,2]]}
    undef r

    def r(val); *a = *yield(); assert_equal(val, a); end
    r([[]]){next *[[]]}
    r([1,2]){next *[1,2]}
    r([1,2]){next *[*[1,2]]}
    undef r

    def r(val); a,b,*c = yield(); assert_equal(val, [a,b,c]); end
    r([nil,nil,[]]){next}
    r([nil,nil,[]]){next nil}
    r([1,nil,[]]){next 1}
    r([nil,nil,[]]){next []}
    r([1,nil,[]]){next [1]}
    r([nil,nil,[]]){next [nil]}
    r([[],nil,[]]){next [[]]}
    r([1,2,[]]){next [1,2]}
    r([nil,nil,[]]){next [*[]]}
    r([1,nil,[]]){next [*[1]]}
    r([1,2,[]]){next [*[1,2]]}
    undef r

    def r(val); a,b,*c = *yield(); assert_equal(val, [a,b,c]); end
    r([[],nil,[]]){next *[[]]}
    r([1,2,[]]){next *[1,2]}
    r([1,2,[]]){next *[*[1,2]]}
    undef r
  end

  def test_massign
    a = nil
    assert(defined?(a))
    assert_nil(a)

    # multiple assignment
    a, b = 1, 2
    assert_equal 1, a
    assert_equal 2, b

    a, b, c = 1, 2, 3
    assert_equal 1, a
    assert_equal 2, b
    assert_equal 3, c

    a = 1
    b = 2
    a, b = b, a
    assert_equal 2, a
    assert_equal 1, b

    a, = 1, 2
    assert_equal 1, a

    a, = 1, 2, 3
    assert_equal 1, a

    a, * = 1, 2, 3
    assert_equal 1, a

    a, *b = 1, 2, 3
    assert_equal 1, a
    assert_equal [2, 3], b

    a, *b, c = 1, 2, 3, 4
    assert_equal 1, a
    assert_equal [2,3], b
    assert_equal 4, c

    a = 1, 2
    assert_equal [1, 2], a

    a = [1, 2], [3, 4]
    assert_equal [[1,2], [3,4]], a

    a, (b, c), d = 1, [2, 3], 4
    assert_equal 1, a
    assert_equal 2, b
    assert_equal 3, c
    assert_equal 4, d

    *a = 1, 2, 3
    assert_equal([1, 2, 3], a)

    *a = 4
    assert_equal([4], a)

    *a = nil
    assert_equal([nil], a)

    a, b = 1
    assert_equal 1, a
    assert_nil b

    a, b = [1, 2]
    assert_equal 1, a
    assert_equal 2, b
  end

  def test_nested_massign
    (a, b), c = [[1, 2], 3]; assert_equal [1,2,3], [a,b,c]
    a, (b, c) = [[1, 2], 3]; assert_equal [[1,2], 3, nil], [a,b,c]
    a, (b, c) = [1, [2, 3]]; assert_equal [1,2,3], [a,b,c]
    (a, b), *c = [[1, 2], 3]; assert_equal [1,2,[3]], [a,b,c]
    (a,b),c,(d,e) = [[1,2],3,[4,5]]; assert_equal [1,2,3,4,5],[a,b,c,d,e]
    (a,*b),c,(d,e,*) = [[1,2],3,[4,5]]; assert_equal [1,[2],3,4,5],[a,b,c,d,e]
    (a,b),c,(d,*e) = [[1,2,3],4,[5,6,7,8]]; assert_equal [1,2,4,5,[6,7,8]],[a,b,c,d,e]
    (a,(b1,b2)),c,(d,e) = [[1,2],3,[4,5]]; assert_equal [1,2,nil,3,4,5],[a,b1,b2,c,d,e]
    (a,(b1,b2)),c,(d,e) = [[1,[21,22]],3,[4,5]]; assert_equal [1,21,22,3,4,5],[a,b1,b2,c,d,e]
  end

  class MyObj
    def to_ary
      [[1,2],[3,4]]
    end
  end

  def test_to_ary_splat
    a, b = MyObj.new
    assert_equal [[1,2],[3,4]], [a,b]
  end

  A = 1
  B = 2
  X, Y = A, B
  class Base
    A = 3
    B = 4
  end

  def test_const_massign
    assert_equal [1,2], [X,Y]
    a, b = Base::A, Base::B
    assert_equal [3,4], [a,b]
  end

  def test_massign_in_cond
    result = eval("if (a, b = MyObj.new); [a, b]; end", nil, __FILE__, __LINE__)
    assert_equal [[1,2],[3,4]], result
  end

  def test_const_assign_order
    assert_raise(RuntimeError) do
      eval('raise("recv")::C = raise(ArgumentError, "bar")')
    end

    assert_raise(RuntimeError) do
      eval('m = 1; m::C = raise("bar")')
    end
  end
end

require_relative 'sentence'
class TestAssignmentGen < Test::Unit::TestCase
  Syntax = {
    :exp => [["0"],
             ["nil"],
             ["false"],
             ["[]"],
             ["[",:exps,"]"]],
    :exps => [[:exp],
              [:exp,",",:exps]],
    :arg => [[:exp]],
    :mrhs => [[:args,",",:arg],
              [:args,",","*",:arg],
              ["*",:arg]],
    :args => [[:arg],
              ["*",:arg],
              [:args,",",:arg],
              [:args,",","*",:arg]],
    :mlhs => [[:mlhs_basic],
              ["(",:mlhs_inner,")"]],
    :mlhs_inner => [[:mlhs_basic],
              ["(",:mlhs_inner,")"]],
    :mlhs_basic => [[:mlhs_head],
                    [:mlhs_head,:mlhs_item],
                    [:mlhs_head,"*",:mlhs_node],
                    [:mlhs_head,"*",:mlhs_node,",",:mlhs_post],
                    [:mlhs_head,"*"],
                    [:mlhs_head,"*",",",           :mlhs_post],
                    [           "*",:mlhs_node],
                    [           "*",:mlhs_node,",",:mlhs_post],
                    [           "*"],
                    [           "*",",",           :mlhs_post]],
    :mlhs_head => [[:mlhs_item,","],
                   [:mlhs_head,:mlhs_item,","]],
    :mlhs_post => [[:mlhs_item],
                   [:mlhs_post,",",:mlhs_item]],
    :mlhs_item => [[:mlhs_node],
                   ["(",:mlhs_inner,")"]],
    :mlhs_node => [["var"]],
    :xassign => [["var"," = ",:exp],
                 ["var"," = ",:mrhs],
                 [:mlhs," = ",:exp],
                 [:mlhs," = ",:mrhs]],
  }

  def rename_var(obj)
    vars = []
    r = obj.subst('var') {
      var = "v#{vars.length}"
      vars << var
      var
    }
    return r, vars
  end

  def expand_except_paren(obj)
    return obj if obj.respond_to? :to_str
    obj.expand {|s|
      !(s[0] == '(' && s[-1] == ')') &&
      !(s[0] == '[' && s[-1] == ']')
    }
  end

  def extract_single_element(ary)
    raise "not a single element array: #{ary.inspect}" if ary.length != 1
    ary[0]
  end

  def emu_assign_ary(lhs, rv, h)
    rv = rv.respond_to?(:to_ary) ? rv : [rv]
    rv = rv.dup
    a = [[]]
    lhs.each {|e|
      if e == ','
        a << []
      else
        a.last << e
      end
    }
    a.pop if a.last == []
    pre = []
    star = post = nil
    a.each {|e|
      if post
        post << e
      elsif e[0] == '*'
        star = e
        post = []
      else
        pre << e
      end
    }
    pre.map! {|e| extract_single_element(e) }
    if star
      if star == ['*']
        star = nil
      else
        star = extract_single_element(star[1..-1])
      end
    end
    post.map! {|e| extract_single_element(e) } if post

    until pre.empty?
      emu_assign_single(pre.shift, rv.shift, h)
    end

    if post
      if rv.length < post.length
        until post.empty?
          emu_assign_single(post.shift, rv.shift, h)
        end
      else
        until post.empty?
          emu_assign_single(post.pop, rv.pop, h)
        end
      end
    end

    if star
      emu_assign_single(star, rv, h)
    end
  end

  def emu_assign_single(lhs, rv, h={})
    if lhs.respond_to? :to_str
      if /\A[a-z0-9]+\z/ =~ lhs
        h[lhs] = rv
      else
        raise "unexpected lhs string: #{lhs.inspect}"
      end
    elsif Sentence === lhs
      if lhs[0] == '(' && lhs[-1] == ')'
        emu_assign_ary(lhs[1...-1], rv, h)
      elsif lhs.length == 1 && String === lhs[0] && /\A[a-z0-9]+\z/ =~ lhs[0]
        h[lhs[0]] = rv
      else
        raise "unexpected lhs sentence: #{lhs.inspect}"
      end
    else
      raise "unexpected lhs: #{lhs.inspect}"
    end
    h
  end

  def emu_assign(assign)
    lhs = expand_except_paren(assign[0])
    rhs = expand_except_paren(assign[2])
    lopen = Sentence === lhs && lhs[-1] != ')' && lhs.any? {|e| e == '*' || e == ',' }
    ropen = Sentence === rhs && rhs[-1] != ']' && rhs.any? {|e| e == '*' || e == ',' }
    lhs = Sentence.new(['(']+lhs.to_a+[')']) if lopen
    begin
      rv = eval((ropen ? ["[",assign[2],"]"] : assign[2]).join(''))
    rescue Exception
      rv = $!.message
    end
    emu_assign_single(lhs, rv)
  end

  def do_assign(assign, vars)
    assign = assign.to_s
    code1 = "#{assign}; [#{vars.join(",")}]"
    assign.gsub!(/\bv\d+\b/, "o.a")
    code2 = "o=[];class << o; self end.send(:define_method,:a=){|v|self << v};#{assign};o"
    begin
      vals1 = eval(code1)
    rescue Exception
      return {:ex=>$!.message}
    end
    begin
      vals2 = eval(code2)
    rescue Exception
      return {:ex=>$!.message}
    end
    assert_equal(vals1, vals2, code1)
    vals = vals1
    h = {}
    [vars, vals].transpose.each {|k,v| h[k] = v }
    h
  end

  def check(assign)
    assign, vars = rename_var(assign)
    sent = assign.to_s
    bruby = do_assign(assign, vars).to_a.sort
    bemu = emu_assign(assign).to_a.sort
    assert_equal(bemu, bruby, sent)
  end

  def test_assignment
    syntax = Sentence.expand_syntax(Syntax)
    Sentence.each(syntax, :xassign, 4) {|assign|
      check(assign)
    }
  end

  def test_optimized_aset
    bug9448 = Class.new do
      def []=(key, new_value)
        '[ruby-core:60071] [Bug #9448]'
      end
    end
    o = bug9448.new
    assert_equal("ok", o['current'] = "ok")
  end

  def test_massign_aref_lhs_splat
    bug11970 = '[ruby-core:72777] [Bug #11970]'
    h = {}
    k = [:key]
    h[*k], = ["ok", "ng"]
    assert_equal("ok", h[:key], bug11970)
  end

  def test_chainged_assign_command
    all_assertions do |a|
      asgn = %w'= +='
      asgn.product(asgn) do |a1, a2|
        stmt = "a #{a1} b #{a2} raise 'x'"
        a.for(stmt) {assert_valid_syntax(stmt)}
      end
    end
  end
end
