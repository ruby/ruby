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

    a = *nil; assert_nil(a)
    a = *1; assert_equal(1, a)
    a = *[]; assert_nil(a)
    a = *[1]; assert_equal(1, a)
    a = *[nil]; assert_nil(a)
    a = *[[]]; assert_equal([], a)
    a = *[1,2]; assert_equal([1,2], a)
    a = *[*[]]; assert_nil(a)
    a = *[*[1]]; assert_equal(1, a)
    a = *[*[1,2]]; assert_equal([1,2], a)

    *a = nil; assert_equal([nil], a)
    *a = 1; assert_equal([1], a)
    *a = []; assert_equal([[]], a)
    *a = [1]; assert_equal([[1]], a)
    *a = [nil]; assert_equal([[nil]], a)
    *a = [[]]; assert_equal([[[]]], a)
    *a = [1,2]; assert_equal([[1,2]], a)
    *a = [*[]]; assert_equal([[]], a)
    *a = [*[1]]; assert_equal([[1]], a)
    *a = [*[1,2]]; assert_equal([[1,2]], a)

    *a = *nil; assert_equal([nil], a)
    *a = *1; assert_equal([1], a)
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

    a,b,*c = *nil; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = *1; assert_equal([1,nil,[]], [a,b,c])
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
    def f; yield nil; end; f {|a| assert_nil(a)}
    def f; yield 1; end; f {|a| assert_equal(1, a)}
    def f; yield []; end; f {|a| assert_equal([], a)}
    def f; yield [1]; end; f {|a| assert_equal([1], a)}
    def f; yield [nil]; end; f {|a| assert_equal([nil], a)}
    def f; yield [[]]; end; f {|a| assert_equal([[]], a)}
    def f; yield [*[]]; end; f {|a| assert_equal([], a)}
    def f; yield [*[1]]; end; f {|a| assert_equal([1], a)}
    def f; yield [*[1,2]]; end; f {|a| assert_equal([1,2], a)}

    def f; yield *nil; end; f {|a| assert_nil(a)}
    def f; yield *1; end; f {|a| assert_equal(1, a)}
    def f; yield *[1]; end; f {|a| assert_equal(1, a)}
    def f; yield *[nil]; end; f {|a| assert_nil(a)}
    def f; yield *[[]]; end; f {|a| assert_equal([], a)}
    def f; yield *[*[1]]; end; f {|a| assert_equal(1, a)}

    def f; yield; end; f {|*a| assert_equal([], a)}
    def f; yield nil; end; f {|*a| assert_equal([nil], a)}
    def f; yield 1; end; f {|*a| assert_equal([1], a)}
    def f; yield []; end; f {|*a| assert_equal([[]], a)}
    def f; yield [1]; end; f {|*a| assert_equal([[1]], a)}
    def f; yield [nil]; end; f {|*a| assert_equal([[nil]], a)}
    def f; yield [[]]; end; f {|*a| assert_equal([[[]]], a)}
    def f; yield [1,2]; end; f {|*a| assert_equal([[1,2]], a)}
    def f; yield [*[]]; end; f {|*a| assert_equal([[]], a)}
    def f; yield [*[1]]; end; f {|*a| assert_equal([[1]], a)}
    def f; yield [*[1,2]]; end; f {|*a| assert_equal([[1,2]], a)}

    def f; yield *nil; end; f {|*a| assert_equal([nil], a)}
    def f; yield *1; end; f {|*a| assert_equal([1], a)}
    def f; yield *[]; end; f {|*a| assert_equal([], a)}
    def f; yield *[1]; end; f {|*a| assert_equal([1], a)}
    def f; yield *[nil]; end; f {|*a| assert_equal([nil], a)}
    def f; yield *[[]]; end; f {|*a| assert_equal([[]], a)}
    def f; yield *[*[]]; end; f {|*a| assert_equal([], a)}
    def f; yield *[*[1]]; end; f {|*a| assert_equal([1], a)}
    def f; yield *[*[1,2]]; end; f {|*a| assert_equal([1,2], a)}

    def f; yield; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield nil; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield 1; end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}
    def f; yield []; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield [1]; end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}
    def f; yield [nil]; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield [[]]; end; f {|a,b,*c| assert_equal([[],nil,[]], [a,b,c])}
    def f; yield [*[]]; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield [*[1]]; end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}
    def f; yield [*[1,2]]; end; f {|a,b,*c| assert_equal([1,2,[]], [a,b,c])}

    def f; yield *nil; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield *1; end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}
    def f; yield *[]; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield *[1]; end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}
    def f; yield *[nil]; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield *[[]]; end; f {|a,b,*c| assert_equal([[],nil,[]], [a,b,c])}
    def f; yield *[*[]]; end; f {|a,b,*c| assert_equal([nil,nil,[]], [a,b,c])}
    def f; yield *[*[1]]; end; f {|a,b,*c| assert_equal([1,nil,[]], [a,b,c])}
    def f; yield *[*[1,2]]; end; f {|a,b,*c| assert_equal([1,2,[]], [a,b,c])}
  end

  def test_return
    def r; return; end; a = r(); assert_nil(a)
    def r; return nil; end; a = r(); assert_nil(a)
    def r; return 1; end; a = r(); assert_equal(1, a)
    def r; return []; end; a = r(); assert_equal([], a)
    def r; return [1]; end; a = r(); assert_equal([1], a)
    def r; return [nil]; end; a = r(); assert_equal([nil], a)
    def r; return [[]]; end; a = r(); assert_equal([[]], a)
    def r; return [*[]]; end; a = r(); assert_equal([], a)
    def r; return [*[1]]; end; a = r(); assert_equal([1], a)
    def r; return [*[1,2]]; end; a = r(); assert_equal([1,2], a)

    def r; return *nil; end; a = r(); assert_nil(a)
    def r; return *1; end; a = r(); assert_equal(1, a)
    def r; return *[]; end; a = r(); assert_nil(a)
    def r; return *[1]; end; a = r(); assert_equal(1, a)
    def r; return *[nil]; end; a = r(); assert_nil(a)
    def r; return *[[]]; end; a = r(); assert_equal([], a)
    def r; return *[*[]]; end; a = r(); assert_nil(a)
    def r; return *[*[1]]; end; a = r(); assert_equal(1, a)
    def r; return *[*[1,2]]; end; a = r(); assert_equal([1,2], a)

    def r; return *nil; end; a = *r(); assert_nil(a)
    def r; return *1; end; a = *r(); assert_equal(1, a)
    def r; return *[]; end; a = *r(); assert_nil(a)
    def r; return *[1]; end; a = *r(); assert_equal(1, a)
    def r; return *[nil]; end; a = *r(); assert_nil(a)
    def r; return *[[]]; end; a = *r(); assert_nil(a)
    def r; return *[*[]]; end; a = *r(); assert_nil(a)
    def r; return *[*[1]]; end; a = *r(); assert_equal(1, a)
    def r; return *[*[1,2]]; end; a = *r(); assert_equal([1,2], a)

    def r; return; end; *a = r(); assert_equal([nil], a)
    def r; return nil; end; *a = r(); assert_equal([nil], a)
    def r; return 1; end; *a = r(); assert_equal([1], a)
    def r; return []; end; *a = r(); assert_equal([[]], a)
    def r; return [1]; end; *a = r(); assert_equal([[1]], a)
    def r; return [nil]; end; *a = r(); assert_equal([[nil]], a)
    def r; return [[]]; end; *a = r(); assert_equal([[[]]], a)
    def r; return [1,2]; end; *a = r(); assert_equal([[1,2]], a)
    def r; return [*[]]; end; *a = r(); assert_equal([[]], a)
    def r; return [*[1]]; end; *a = r(); assert_equal([[1]], a)
    def r; return [*[1,2]]; end; *a = r(); assert_equal([[1,2]], a)

    def r; return *nil; end; *a = r(); assert_equal([nil], a)
    def r; return *1; end; *a = r(); assert_equal([1], a)
    def r; return *[]; end; *a = r(); assert_equal([nil], a)
    def r; return *[1]; end; *a = r(); assert_equal([1], a)
    def r; return *[nil]; end; *a = r(); assert_equal([nil], a)
    def r; return *[[]]; end; *a = r(); assert_equal([[]], a)
    def r; return *[1,2]; end; *a = r(); assert_equal([[1,2]], a)
    def r; return *[*[]]; end; *a = r(); assert_equal([nil], a)
    def r; return *[*[1]]; end; *a = r(); assert_equal([1], a)
    def r; return *[*[1,2]]; end; *a = r(); assert_equal([[1,2]], a)

    def r; return *nil; end; *a = *r(); assert_equal([nil], a)
    def r; return *1; end; *a = *r(); assert_equal([1], a)
    def r; return *[]; end; *a = *r(); assert_equal([nil], a)
    def r; return *[1]; end; *a = *r(); assert_equal([1], a)
    def r; return *[nil]; end; *a = *r(); assert_equal([nil], a)
    def r; return *[[]]; end; *a = *r(); assert_equal([], a)
    def r; return *[1,2]; end; *a = *r(); assert_equal([1,2], a)
    def r; return *[*[]]; end; *a = *r(); assert_equal([nil], a)
    def r; return *[*[1]]; end; *a = *r(); assert_equal([1], a)
    def r; return *[*[1,2]]; end; *a = *r(); assert_equal([1,2], a)

    def r; return; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return nil; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return 1; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c])
    def r; return []; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return [1]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c])
    def r; return [nil]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return [[]]; end; a,b,*c = r(); assert_equal([[],nil,[]], [a,b,c])
    def r; return [1,2]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c])
    def r; return [*[]]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return [*[1]]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c])
    def r; return [*[1,2]]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c])

    def r; return *nil; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return *1; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c])
    def r; return *[]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return *[1]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c])
    def r; return *[nil]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return *[[]]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return *[1,2]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c])
    def r; return *[*[]]; end; a,b,*c = r(); assert_equal([nil,nil,[]], [a,b,c])
    def r; return *[*[1]]; end; a,b,*c = r(); assert_equal([1,nil,[]], [a,b,c])
    def r; return *[*[1,2]]; end; a,b,*c = r(); assert_equal([1,2,[]], [a,b,c])
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

    a = loop do break *nil; end; assert_nil(a)
    a = loop do break *1; end; assert_equal(1, a)
    a = loop do break *[]; end; assert_nil(a)
    a = loop do break *[1]; end; assert_equal(1, a)
    a = loop do break *[nil]; end; assert_nil(a)
    a = loop do break *[[]]; end; assert_equal([], a)
    a = loop do break *[*[]]; end; assert_nil(a)
    a = loop do break *[*[1]]; end; assert_equal(1, a)
    a = loop do break *[*[1,2]]; end; assert_equal([1,2], a)

    *a = loop do break; end; assert_equal([nil], a)
    *a = loop do break nil; end; assert_equal([nil], a)
    *a = loop do break 1; end; assert_equal([1], a)
    *a = loop do break []; end; assert_equal([[]], a)
    *a = loop do break [1]; end; assert_equal([[1]], a)
    *a = loop do break [nil]; end; assert_equal([[nil]], a)
    *a = loop do break [[]]; end; assert_equal([[[]]], a)
    *a = loop do break [1,2]; end; assert_equal([[1,2]], a)
    *a = loop do break [*[]]; end; assert_equal([[]], a)
    *a = loop do break [*[1]]; end; assert_equal([[1]], a)
    *a = loop do break [*[1,2]]; end; assert_equal([[1,2]], a)

    *a = loop do break *nil; end; assert_equal([nil], a)
    *a = loop do break *1; end; assert_equal([1], a)
    *a = loop do break *[]; end; assert_equal([nil], a)
    *a = loop do break *[1]; end; assert_equal([1], a)
    *a = loop do break *[nil]; end; assert_equal([nil], a)
    *a = loop do break *[[]]; end; assert_equal([[]], a)
    *a = loop do break *[1,2]; end; assert_equal([[1,2]], a)
    *a = loop do break *[*[]]; end; assert_equal([nil], a)
    *a = loop do break *[*[1]]; end; assert_equal([1], a)
    *a = loop do break *[*[1,2]]; end; assert_equal([[1,2]], a)

    *a = *loop do break *nil; end; assert_equal([nil], a)
    *a = *loop do break *1; end; assert_equal([1], a)
    *a = *loop do break *[]; end; assert_equal([nil], a)
    *a = *loop do break *[1]; end; assert_equal([1], a)
    *a = *loop do break *[nil]; end; assert_equal([nil], a)
    *a = *loop do break *[[]]; end; assert_equal([], a)
    *a = *loop do break *[1,2]; end; assert_equal([1,2], a)
    *a = *loop do break *[*[]]; end; assert_equal([nil], a)
    *a = *loop do break *[*[1]]; end; assert_equal([1], a)
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

    a,b,*c = loop do break *nil; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break *1; end; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = loop do break *[]; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break *[1]; end; assert_equal([1,nil,[]], [a,b,c])
    a,b,*c = loop do break *[nil]; end; assert_equal([nil,nil,[]], [a,b,c])
    a,b,*c = loop do break *[[]]; end; assert_equal([nil,nil,[]], [a,b,c])
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

    r(nil){next *nil}
    r(1){next *1}
    r(nil){next *[]}
    r(1){next *[1]}
    r(nil){next *[nil]}
    r([]){next *[[]]}
    r(nil){next *[*[]]}
    r(1){next *[*[1]]}
    r([1,2]){next *[*[1,2]]}

    def r(val); *a = yield(); assert_equal(val, a); end
    r([nil]){next}
    r([nil]){next nil}
    r([1]){next 1}
    r([[]]){next []}
    r([[1]]){next [1]}
    r([[nil]]){next [nil]}
    r([[[]]]){next [[]]}
    r([[1,2]]){next [1,2]}
    r([[]]){next [*[]]}
    r([[1]]){next [*[1]]}
    r([[1,2]]){next [*[1,2]]}

    def r(val); *a = *yield(); assert_equal(val, a); end
    r([nil]){next *nil}
    r([1]){next *1}
    r([nil]){next *[]}
    r([1]){next *[1]}
    r([nil]){next *[nil]}
    r([]){next *[[]]}
    r([1,2]){next *[1,2]}
    r([nil]){next *[*[]]}
    r([1]){next *[*[1]]}
    r([1,2]){next *[*[1,2]]}

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

    def r(val); a,b,*c = *yield(); assert_equal(val, [a,b,c]); end
    r([nil,nil,[]]){next *nil}
    r([1,nil,[]]){next *1}
    r([nil,nil,[]]){next *[]}
    r([1,nil,[]]){next *[1]}
    r([nil,nil,[]]){next *[nil]}
    r([nil,nil,[]]){next *[[]]}
    r([1,2,[]]){next *[1,2]}
    r([nil,nil,[]]){next *[*[]]}
    r([1,nil,[]]){next *[*[1]]}
    r([1,2,[]]){next *[*[1,2]]}
  end

  def test_assign2
    a = nil
    assert(defined?(a))
    assert_nil(a)

    # multiple asignment
    a, b = 1, 2
    assert(a == 1 && b == 2)

    a, b = b, a
    assert(a == 2 && b == 1)

    a, = 1,2
    assert_equal(1, a)

    a, *b = 1, 2, 3
    assert(a == 1 && b == [2, 3])

    a, (b, c), d = 1, [2, 3], 4
    assert(a == 1 && b == 2 && c == 3 && d == 4)

    *a = 1, 2, 3
    assert_equal([1, 2, 3], a)

    *a = 4
    assert_equal([4], a)

    *a = nil
    assert_equal([nil], a)
  end
end
