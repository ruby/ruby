require 'test/unit'

$KCODE = 'none'

class TestAssignment < Test::Unit::TestCase
  def test_assign
    a=[]; a[0] ||= "bar";
    assert_equal(a[0], "bar")
    h={}; h["foo"] ||= "bar";
    assert_equal(h["foo"], "bar")
    
    aa = 5
    aa ||= 25
    assert_equal(aa, 5)
    bb ||= 25
    assert_equal(bb, 25)
    cc &&=33
    assert_equal(cc, nil)
    cc = 5
    cc &&=44
    assert_equal(cc, 44)
    
    a = nil; assert_equal(a, nil)
    a = 1; assert_equal(a, 1)
    a = []; assert_equal(a, [])
    a = [1]; assert_equal(a, [1])
    a = [nil]; assert_equal(a, [nil])
    a = [[]]; assert_equal(a, [[]])
    a = [1,2]; assert_equal(a, [1,2])
    a = [*[]]; assert_equal(a, [])
    a = [*[1]]; assert_equal(a, [1])
    a = [*[1,2]]; assert_equal(a, [1,2])
    
    a = *nil; assert_equal(a, nil)
    a = *1; assert_equal(a, 1)
    a = *[]; assert_equal(a, nil)
    a = *[1]; assert_equal(a, 1)
    a = *[nil]; assert_equal(a, nil)
    a = *[[]]; assert_equal(a, [])
    a = *[1,2]; assert_equal(a, [1,2])
    a = *[*[]]; assert_equal(a, nil)
    a = *[*[1]]; assert_equal(a, 1)
    a = *[*[1,2]]; assert_equal(a, [1,2])
    
    *a = nil; assert_equal(a, [nil])
    *a = 1; assert_equal(a, [1])
    *a = []; assert_equal(a, [[]])
    *a = [1]; assert_equal(a, [[1]])
    *a = [nil]; assert_equal(a, [[nil]])
    *a = [[]]; assert_equal(a, [[[]]])
    *a = [1,2]; assert_equal(a, [[1,2]])
    *a = [*[]]; assert_equal(a, [[]])
    *a = [*[1]]; assert_equal(a, [[1]])
    *a = [*[1,2]]; assert_equal(a, [[1,2]])
    
    *a = *nil; assert_equal(a, [nil])
    *a = *1; assert_equal(a, [1])
    *a = *[]; assert_equal(a, [])
    *a = *[1]; assert_equal(a, [1])
    *a = *[nil]; assert_equal(a, [nil])
    *a = *[[]]; assert_equal(a, [[]])
    *a = *[1,2]; assert_equal(a, [1,2])
    *a = *[*[]]; assert_equal(a, [])
    *a = *[*[1]]; assert_equal(a, [1])
    *a = *[*[1,2]]; assert_equal(a, [1,2])
    
    a,b,*c = nil; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = 1; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = []; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = [1]; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = [nil]; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = [[]]; assert_equal([a,b,c], [[],nil,[]])
    a,b,*c = [1,2]; assert_equal([a,b,c], [1,2,[]])
    a,b,*c = [*[]]; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = [*[1]]; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = [*[1,2]]; assert_equal([a,b,c], [1,2,[]])
    
    a,b,*c = *nil; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = *1; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = *[]; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = *[1]; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = *[nil]; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = *[[]]; assert_equal([a,b,c], [[],nil,[]])
    a,b,*c = *[1,2]; assert_equal([a,b,c], [1,2,[]])
    a,b,*c = *[*[]]; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = *[*[1]]; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = *[*[1,2]]; assert_equal([a,b,c], [1,2,[]])
  end

  def test_yield
    def f; yield nil; end; f {|a| assert_equal(a, nil)}
    def f; yield 1; end; f {|a| assert_equal(a, 1)}
    def f; yield []; end; f {|a| assert_equal(a, [])}
    def f; yield [1]; end; f {|a| assert_equal(a, [1])}
    def f; yield [nil]; end; f {|a| assert_equal(a, [nil])}
    def f; yield [[]]; end; f {|a| assert_equal(a, [[]])}
    def f; yield [*[]]; end; f {|a| assert_equal(a, [])}
    def f; yield [*[1]]; end; f {|a| assert_equal(a, [1])}
    def f; yield [*[1,2]]; end; f {|a| assert_equal(a, [1,2])}
    
    def f; yield *nil; end; f {|a| assert_equal(a, nil)}
    def f; yield *1; end; f {|a| assert_equal(a, 1)}
    def f; yield *[1]; end; f {|a| assert_equal(a, 1)}
    def f; yield *[nil]; end; f {|a| assert_equal(a, nil)}
    def f; yield *[[]]; end; f {|a| assert_equal(a, [])}
    def f; yield *[*[1]]; end; f {|a| assert_equal(a, 1)}
    
    def f; yield; end; f {|*a| assert_equal(a, [])}
    def f; yield nil; end; f {|*a| assert_equal(a, [nil])}
    def f; yield 1; end; f {|*a| assert_equal(a, [1])}
    def f; yield []; end; f {|*a| assert_equal(a, [[]])}
    def f; yield [1]; end; f {|*a| assert_equal(a, [[1]])}
    def f; yield [nil]; end; f {|*a| assert_equal(a, [[nil]])}
    def f; yield [[]]; end; f {|*a| assert_equal(a, [[[]]])}
    def f; yield [1,2]; end; f {|*a| assert_equal(a, [[1,2]])}
    def f; yield [*[]]; end; f {|*a| assert_equal(a, [[]])}
    def f; yield [*[1]]; end; f {|*a| assert_equal(a, [[1]])}
    def f; yield [*[1,2]]; end; f {|*a| assert_equal(a, [[1,2]])}
    
    def f; yield *nil; end; f {|*a| assert_equal(a, [nil])}
    def f; yield *1; end; f {|*a| assert_equal(a, [1])}
    def f; yield *[]; end; f {|*a| assert_equal(a, [])}
    def f; yield *[1]; end; f {|*a| assert_equal(a, [1])}
    def f; yield *[nil]; end; f {|*a| assert_equal(a, [nil])}
    def f; yield *[[]]; end; f {|*a| assert_equal(a, [[]])}
    def f; yield *[*[]]; end; f {|*a| assert_equal(a, [])}
    def f; yield *[*[1]]; end; f {|*a| assert_equal(a, [1])}
    def f; yield *[*[1,2]]; end; f {|*a| assert_equal(a, [1,2])}
    
    def f; yield; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield nil; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield 1; end; f {|a,b,*c| assert_equal([a,b,c], [1,nil,[]])}
    def f; yield []; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield [1]; end; f {|a,b,*c| assert_equal([a,b,c], [1,nil,[]])}
    def f; yield [nil]; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield [[]]; end; f {|a,b,*c| assert_equal([a,b,c], [[],nil,[]])}
    def f; yield [*[]]; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield [*[1]]; end; f {|a,b,*c| assert_equal([a,b,c], [1,nil,[]])}
    def f; yield [*[1,2]]; end; f {|a,b,*c| assert_equal([a,b,c], [1,2,[]])}
    
    def f; yield *nil; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield *1; end; f {|a,b,*c| assert_equal([a,b,c], [1,nil,[]])}
    def f; yield *[]; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield *[1]; end; f {|a,b,*c| assert_equal([a,b,c], [1,nil,[]])}
    def f; yield *[nil]; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield *[[]]; end; f {|a,b,*c| assert_equal([a,b,c], [[],nil,[]])}
    def f; yield *[*[]]; end; f {|a,b,*c| assert_equal([a,b,c], [nil,nil,[]])}
    def f; yield *[*[1]]; end; f {|a,b,*c| assert_equal([a,b,c], [1,nil,[]])}
    def f; yield *[*[1,2]]; end; f {|a,b,*c| assert_equal([a,b,c], [1,2,[]])}
  end

  def test_return
    def r; return; end; a = r(); assert_equal(a, nil)
    def r; return nil; end; a = r(); assert_equal(a, nil)
    def r; return 1; end; a = r(); assert_equal(a, 1)
    def r; return []; end; a = r(); assert_equal(a, [])
    def r; return [1]; end; a = r(); assert_equal(a, [1])
    def r; return [nil]; end; a = r(); assert_equal(a, [nil])
    def r; return [[]]; end; a = r(); assert_equal(a, [[]])
    def r; return [*[]]; end; a = r(); assert_equal(a, [])
    def r; return [*[1]]; end; a = r(); assert_equal(a, [1])
    def r; return [*[1,2]]; end; a = r(); assert_equal(a, [1,2])
    
    def r; return *nil; end; a = r(); assert_equal(a, nil)
    def r; return *1; end; a = r(); assert_equal(a, 1)
    def r; return *[]; end; a = r(); assert_equal(a, nil)
    def r; return *[1]; end; a = r(); assert_equal(a, 1)
    def r; return *[nil]; end; a = r(); assert_equal(a, nil)
    def r; return *[[]]; end; a = r(); assert_equal(a, [])
    def r; return *[*[]]; end; a = r(); assert_equal(a, nil)
    def r; return *[*[1]]; end; a = r(); assert_equal(a, 1)
    def r; return *[*[1,2]]; end; a = r(); assert_equal(a, [1,2])
    
    def r; return *nil; end; a = *r(); assert_equal(a, nil)
    def r; return *1; end; a = *r(); assert_equal(a, 1)
    def r; return *[]; end; a = *r(); assert_equal(a, nil)
    def r; return *[1]; end; a = *r(); assert_equal(a, 1)
    def r; return *[nil]; end; a = *r(); assert_equal(a, nil)
    def r; return *[[]]; end; a = *r(); assert_equal(a, nil)
    def r; return *[*[]]; end; a = *r(); assert_equal(a, nil)
    def r; return *[*[1]]; end; a = *r(); assert_equal(a, 1)
    def r; return *[*[1,2]]; end; a = *r(); assert_equal(a, [1,2])
    
    def r; return; end; *a = r(); assert_equal(a, [nil])
    def r; return nil; end; *a = r(); assert_equal(a, [nil])
    def r; return 1; end; *a = r(); assert_equal(a, [1])
    def r; return []; end; *a = r(); assert_equal(a, [[]])
    def r; return [1]; end; *a = r(); assert_equal(a, [[1]])
    def r; return [nil]; end; *a = r(); assert_equal(a, [[nil]])
    def r; return [[]]; end; *a = r(); assert_equal(a, [[[]]])
    def r; return [1,2]; end; *a = r(); assert_equal(a, [[1,2]])
    def r; return [*[]]; end; *a = r(); assert_equal(a, [[]])
    def r; return [*[1]]; end; *a = r(); assert_equal(a, [[1]])
    def r; return [*[1,2]]; end; *a = r(); assert_equal(a, [[1,2]])
    
    def r; return *nil; end; *a = r(); assert_equal(a, [nil])
    def r; return *1; end; *a = r(); assert_equal(a, [1])
    def r; return *[]; end; *a = r(); assert_equal(a, [nil])
    def r; return *[1]; end; *a = r(); assert_equal(a, [1])
    def r; return *[nil]; end; *a = r(); assert_equal(a, [nil])
    def r; return *[[]]; end; *a = r(); assert_equal(a, [[]])
    def r; return *[1,2]; end; *a = r(); assert_equal(a, [[1,2]])
    def r; return *[*[]]; end; *a = r(); assert_equal(a, [nil])
    def r; return *[*[1]]; end; *a = r(); assert_equal(a, [1])
    def r; return *[*[1,2]]; end; *a = r(); assert_equal(a, [[1,2]])
    
    def r; return *nil; end; *a = *r(); assert_equal(a, [nil])
    def r; return *1; end; *a = *r(); assert_equal(a, [1])
    def r; return *[]; end; *a = *r(); assert_equal(a, [nil])
    def r; return *[1]; end; *a = *r(); assert_equal(a, [1])
    def r; return *[nil]; end; *a = *r(); assert_equal(a, [nil])
    def r; return *[[]]; end; *a = *r(); assert_equal(a, [])
    def r; return *[1,2]; end; *a = *r(); assert_equal(a, [1,2])
    def r; return *[*[]]; end; *a = *r(); assert_equal(a, [nil])
    def r; return *[*[1]]; end; *a = *r(); assert_equal(a, [1])
    def r; return *[*[1,2]]; end; *a = *r(); assert_equal(a, [1,2])
    
    def r; return; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return nil; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return 1; end; a,b,*c = r(); assert_equal([a,b,c], [1,nil,[]])
    def r; return []; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return [1]; end; a,b,*c = r(); assert_equal([a,b,c], [1,nil,[]])
    def r; return [nil]; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return [[]]; end; a,b,*c = r(); assert_equal([a,b,c], [[],nil,[]])
    def r; return [1,2]; end; a,b,*c = r(); assert_equal([a,b,c], [1,2,[]])
    def r; return [*[]]; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return [*[1]]; end; a,b,*c = r(); assert_equal([a,b,c], [1,nil,[]])
    def r; return [*[1,2]]; end; a,b,*c = r(); assert_equal([a,b,c], [1,2,[]])
    
    def r; return *nil; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return *1; end; a,b,*c = r(); assert_equal([a,b,c], [1,nil,[]])
    def r; return *[]; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return *[1]; end; a,b,*c = r(); assert_equal([a,b,c], [1,nil,[]])
    def r; return *[nil]; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return *[[]]; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return *[1,2]; end; a,b,*c = r(); assert_equal([a,b,c], [1,2,[]])
    def r; return *[*[]]; end; a,b,*c = r(); assert_equal([a,b,c], [nil,nil,[]])
    def r; return *[*[1]]; end; a,b,*c = r(); assert_equal([a,b,c], [1,nil,[]])
    def r; return *[*[1,2]]; end; a,b,*c = r(); assert_equal([a,b,c], [1,2,[]])
  end

  def test_lambda
    f = lambda {|r,| assert_equal([], r)}
    f.call([], *[])
    
    f = lambda {|r,*l| assert_equal([], r); assert_equal([1], l)}
    f.call([], *[1])
    
    f = lambda{|x| x}
    assert_equal(f.call(42), 42)
    assert_equal(f.call([42]), [42])
    assert_equal(f.call([[42]]), [[42]])
    assert_equal(f.call([42,55]), [42,55])
    
    f = lambda{|x,| x}
    assert_equal(f.call(42), 42)
    assert_equal(f.call([42]), [42])
    assert_equal(f.call([[42]]), [[42]])
    assert_equal(f.call([42,55]), [42,55])
    
    f = lambda{|*x| x}
    assert_equal(f.call(42), [42])
    assert_equal(f.call([42]), [[42]])
    assert_equal(f.call([[42]]), [[[42]]])
    assert_equal(f.call([42,55]), [[42,55]])
    assert_equal(f.call(42,55), [42,55])
  end

  def test_multi
    a,=*[1]
    assert_equal(a, 1)
    a,=*[[1]]
    assert_equal(a, [1])
    a,=*[[[1]]]
    assert_equal(a, [[1]])
    
    x, (y, z) = 1, 2, 3
    assert_equal([1,2,nil], [x,y,z])
    x, (y, z) = 1, [2,3]
    assert_equal([1,2,3], [x,y,z])
    x, (y, z) = 1, [2]
    assert_equal([1,2,nil], [x,y,z])
  end

  def test_break
    a = loop do break; end; assert_equal(a, nil)
    a = loop do break nil; end; assert_equal(a, nil)
    a = loop do break 1; end; assert_equal(a, 1)
    a = loop do break []; end; assert_equal(a, [])
    a = loop do break [1]; end; assert_equal(a, [1])
    a = loop do break [nil]; end; assert_equal(a, [nil])
    a = loop do break [[]]; end; assert_equal(a, [[]])
    a = loop do break [*[]]; end; assert_equal(a, [])
    a = loop do break [*[1]]; end; assert_equal(a, [1])
    a = loop do break [*[1,2]]; end; assert_equal(a, [1,2])
    
    a = loop do break *nil; end; assert_equal(a, nil)
    a = loop do break *1; end; assert_equal(a, 1)
    a = loop do break *[]; end; assert_equal(a, nil)
    a = loop do break *[1]; end; assert_equal(a, 1)
    a = loop do break *[nil]; end; assert_equal(a, nil)
    a = loop do break *[[]]; end; assert_equal(a, [])
    a = loop do break *[*[]]; end; assert_equal(a, nil)
    a = loop do break *[*[1]]; end; assert_equal(a, 1)
    a = loop do break *[*[1,2]]; end; assert_equal(a, [1,2])
    
    *a = loop do break; end; assert_equal(a, [nil])
    *a = loop do break nil; end; assert_equal(a, [nil])
    *a = loop do break 1; end; assert_equal(a, [1])
    *a = loop do break []; end; assert_equal(a, [[]])
    *a = loop do break [1]; end; assert_equal(a, [[1]])
    *a = loop do break [nil]; end; assert_equal(a, [[nil]])
    *a = loop do break [[]]; end; assert_equal(a, [[[]]])
    *a = loop do break [1,2]; end; assert_equal(a, [[1,2]])
    *a = loop do break [*[]]; end; assert_equal(a, [[]])
    *a = loop do break [*[1]]; end; assert_equal(a, [[1]])
    *a = loop do break [*[1,2]]; end; assert_equal(a, [[1,2]])
    
    *a = loop do break *nil; end; assert_equal(a, [nil])
    *a = loop do break *1; end; assert_equal(a, [1])
    *a = loop do break *[]; end; assert_equal(a, [nil])
    *a = loop do break *[1]; end; assert_equal(a, [1])
    *a = loop do break *[nil]; end; assert_equal(a, [nil])
    *a = loop do break *[[]]; end; assert_equal(a, [[]])
    *a = loop do break *[1,2]; end; assert_equal(a, [[1,2]])
    *a = loop do break *[*[]]; end; assert_equal(a, [nil])
    *a = loop do break *[*[1]]; end; assert_equal(a, [1])
    *a = loop do break *[*[1,2]]; end; assert_equal(a, [[1,2]])
    
    *a = *loop do break *nil; end; assert_equal(a, [nil])
    *a = *loop do break *1; end; assert_equal(a, [1])
    *a = *loop do break *[]; end; assert_equal(a, [nil])
    *a = *loop do break *[1]; end; assert_equal(a, [1])
    *a = *loop do break *[nil]; end; assert_equal(a, [nil])
    *a = *loop do break *[[]]; end; assert_equal(a, [])
    *a = *loop do break *[1,2]; end; assert_equal(a, [1,2])
    *a = *loop do break *[*[]]; end; assert_equal(a, [nil])
    *a = *loop do break *[*[1]]; end; assert_equal(a, [1])
    *a = *loop do break *[*[1,2]]; end; assert_equal(a, [1,2])
    
    a,b,*c = loop do break; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break nil; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break 1; end; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = loop do break []; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break [1]; end; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = loop do break [nil]; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break [[]]; end; assert_equal([a,b,c], [[],nil,[]])
    a,b,*c = loop do break [1,2]; end; assert_equal([a,b,c], [1,2,[]])
    a,b,*c = loop do break [*[]]; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break [*[1]]; end; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = loop do break [*[1,2]]; end; assert_equal([a,b,c], [1,2,[]])
    
    a,b,*c = loop do break *nil; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break *1; end; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = loop do break *[]; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break *[1]; end; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = loop do break *[nil]; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break *[[]]; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break *[1,2]; end; assert_equal([a,b,c], [1,2,[]])
    a,b,*c = loop do break *[*[]]; end; assert_equal([a,b,c], [nil,nil,[]])
    a,b,*c = loop do break *[*[1]]; end; assert_equal([a,b,c], [1,nil,[]])
    a,b,*c = loop do break *[*[1,2]]; end; assert_equal([a,b,c], [1,2,[]])
  end

  def test_next
    def r(val); a = yield(); assert_equal(a, val); end
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
    
    def r(val); *a = yield(); assert_equal(a, val); end
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
    
    def r(val); *a = *yield(); assert_equal(a, val); end
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
    
    def r(val); a,b,*c = yield(); assert_equal([a,b,c], val); end
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
    
    def r(val); a,b,*c = *yield(); assert_equal([a,b,c], val); end
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
    assert_equal(a, nil)
    
    # multiple asignment
    a, b = 1, 2
    assert(a == 1 && b == 2)
    
    a, b = b, a
    assert(a == 2 && b == 1)
    
    a, = 1,2
    assert_equal(a, 1)
    
    a, *b = 1, 2, 3
    assert(a == 1 && b == [2, 3])
    
    a, (b, c), d = 1, [2, 3], 4
    assert(a == 1 && b == 2 && c == 3 && d == 4)
    
    *a = 1, 2, 3
    assert_equal(a, [1, 2, 3])
    
    *a = 4
    assert_equal(a, [4])
    
    *a = nil
    assert_equal(a, [nil])
  end
end
