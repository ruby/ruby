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

    a = *[]; assert_equal([], a)
    a = *[1]; assert_equal([1], a)
    a = *[nil]; assert_equal([nil], a)
    a = *[[]]; assert_equal([[]], a)
    a = *[1,2]; assert_equal([1,2], a)
    a = *[*[]]; assert_equal([], a)
    a = *[*[1]]; assert_equal([1], a)
    a = *[*[1,2]]; assert_equal([1,2], a)

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

    *a = *[]; assert_equal([], a)
    *a = *[1]; assert_equal([1], a)
    *a = *[nil]; assert_equal([nil], a)
    *a = *[[]]; assert_equal([[]], a)
    *a = *[1,2]; assert_equal([1,2], a)
    *a = *[*[]]; assert_equal([], a)
    *a = *[*[1]]; assert_equal([1], a)
    *a = *[*[1,2]]; assert_equal([1,2], a)

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

    a,b,*c = *[]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = *[1]; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = *[nil]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = *[[]]; assert_equal([[],nil,[]], [a,b,c])
    a,b,*c = *[1,2]; assert_equal([1,2,[]], [a,b,c])
    a,b,*c = *[*[]]; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = *[*[1]]; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = *[*[1,2]]; assert_equal([1,2,[]], [a,b,c])
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

    def f; yield(*[1]); end; f {|a| assert_equal([1], a)}; undef f
    def f; yield(*[nil]); end; f {|a| assert_equal([nil], a)}; undef f
    def f; yield(*[[]]); end; f {|a| assert_equal([[]], a)}; undef f
    def f; yield(*[*[1]]); end; f {|a| assert_equal([1], a)}; undef f

    def f; yield; end; f {|*a| assert_equal([], a)}; undef f
    def f; yield(nil); end; f {|*a| assert_equal([nil], a)}; undef f
    def f; yield(1); end; f {|*a| assert_equal([1], a)}; undef f
    def f; yield([]); end; f {|*a| assert_equal([], a)}; undef f
    def f; yield([1]); end; f {|*a| assert_equal([1], a)}; undef f
    def f; yield([nil]); end; f {|*a| assert_equal([nil], a)}; undef f
    def f; yield([[]]); end; f {|*a| assert_equal([[]], a)}; undef f
    def f; yield([1,2]); end; f {|*a| assert_equal([1,2], a)}; undef f
    def f; yield([*[]]); end; f {|*a| assert_equal([], a)}; undef f
    def f; yield([*[1]]); end; f {|*a| assert_equal([1], a)}; undef f
    def f; yield([*[1,2]]); end; f {|*a| assert_equal([1,2], a)}; undef f

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
    def f; yield(*[[]]); end; f {|a,b,*c| assert_equal([[],nil,[]], [a,b,c])}; undef f
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

    # multiple asignment
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

    # not supported yet
    #a, *b, c = 1, 2, 3, 4
    #assert_equal 1, a
    #assert_equal [2,3], b
    #assert_equal 4, c

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
end
