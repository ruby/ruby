require 'test/unit'

$KCODE = 'none'

class Array
  def iter_test1
    collect{|e| [e, yield(e)]}.sort{|a,b|a[1]<=>b[1]}
  end
  def iter_test2
    a = collect{|e| [e, yield(e)]}
    a.sort{|a,b|a[1]<=>b[1]}
  end
end

class TestIterator < Test::Unit::TestCase
  def ttt
    assert(iterator?)
  end

  def test_iterator
    assert(!iterator?)

    ttt{}

    # yield at top level	!! here's not toplevel
    assert(!defined?(yield))
  end

  def test_array
    $x = [1, 2, 3, 4]
    $y = []

    # iterator over array
    for i in $x
      $y.push i
    end
    assert($x == $y)
  end

  def tt
    1.upto(10) {|i|
      yield i
    }
  end

  def tt2(dummy)
    yield 1
  end

  def tt3(&block)
    tt2(raise(ArgumentError,""),&block)
  end

  def test_nested_iterator
    i = 0
    tt{|i| break if i == 5}
    assert(i == 5)

    $x = false
    begin
      tt3{}
    rescue ArgumentError
      $x = true
    rescue Exception
    end
    assert($x)
  end

  # iterator break/redo/next/retry
  def test_break
    done = true
    loop{
      break
      done = false			# should not reach here
    }
    assert(done)

    done = false
    $bad = false
    loop {
      break if done
      done = true
      next
      $bad = true			# should not reach here
    }
    assert(!$bad)

    done = false
    $bad = false
    loop {
      break if done
      done = true
      redo
      $bad = true			# should not reach here
    }
    assert(!$bad)

    $x = []
    for i in 1 .. 7
      $x.push i
    end
    assert($x.size == 7)
    assert($x == [1, 2, 3, 4, 5, 6, 7])

    $done = false
    $x = []
    for i in 1 .. 7			# see how retry works in iterator loop
      if i == 4 and not $done
	$done = true
	retry
      end
      $x.push(i)
    end
    assert($x.size == 10)
    assert($x == [1, 2, 3, 1, 2, 3, 4, 5, 6, 7])
  end

  def test_append_method_to_built_in_class
    $x = [[1,2],[3,4],[5,6]]
    assert($x.iter_test1{|x|x} == $x.iter_test2{|x|x})
  end

  class IterTest
    def initialize(e); @body = e; end

    def each0(&block); @body.each(&block); end
    def each1(&block); @body.each {|*x| block.call(*x) } end
    def each2(&block); @body.each {|*x| block.call(x) } end
    def each3(&block); @body.each {|x| block.call(*x) } end
    def each4(&block); @body.each {|x| block.call(x) } end
    def each5; @body.each {|*x| yield(*x) } end
    def each6; @body.each {|*x| yield(x) } end
    def each7; @body.each {|x| yield(*x) } end
    def each8; @body.each {|x| yield(x) } end

    def f(a)
      a
    end
  end

  def test_itertest
    assert(IterTest.new(nil).method(:f).to_proc.call([1]) == [1])
    m = /\w+/.match("abc")
    assert(IterTest.new(nil).method(:f).to_proc.call([m]) == [m])

    IterTest.new([0]).each0 {|x| assert(x == 0)}
    IterTest.new([1]).each1 {|x| assert(x == 1)}
    IterTest.new([2]).each2 {|x| assert(x == [2])}
    IterTest.new([3]).each3 {|x| assert(x == 3)}
    IterTest.new([4]).each4 {|x| assert(x == 4)}
    IterTest.new([5]).each5 {|x| assert(x == 5)}
    IterTest.new([6]).each6 {|x| assert(x == [6])}
    IterTest.new([7]).each7 {|x| assert(x == 7)}
    IterTest.new([8]).each8 {|x| assert(x == 8)}

    IterTest.new([[0]]).each0 {|x| assert(x == [0])}
    IterTest.new([[1]]).each1 {|x| assert(x == [1])}
    IterTest.new([[2]]).each2 {|x| assert(x == [[2]])}
    IterTest.new([[3]]).each3 {|x| assert(x == 3)}
    IterTest.new([[4]]).each4 {|x| assert(x == [4])}
    IterTest.new([[5]]).each5 {|x| assert(x == [5])}
    IterTest.new([[6]]).each6 {|x| assert(x == [[6]])}
    IterTest.new([[7]]).each7 {|x| assert(x == 7)}
    IterTest.new([[8]]).each8 {|x| assert(x == [8])}

    IterTest.new([[0,0]]).each0 {|x| assert(x == [0,0])}
    IterTest.new([[8,8]]).each8 {|x| assert(x == [8,8])}
  end

  def m(var)
    assert(var)
  end

  def m1
    m(block_given?)
  end

  def m2
    m(block_given?,&proc{})
  end

  def test_foo
    m1{p 'test'}
    m2{p 'test'}
  end

  class C
    include Enumerable
    def initialize
      @a = [1,2,3]
    end
    def each(&block)
      @a.each(&block)
    end
  end

  def test_collect
    assert(C.new.collect{|n| n} == [1,2,3])
  end

  def test_proc
    assert(Proc == lambda{}.class)
    assert(Proc == Proc.new{}.class)
    lambda{|a|assert(a==1)}.call(1)
  end

  def block_test(klass, &block)
    assert(klass === block)
  end

  def test_block
    block_test(NilClass)
    block_test(Proc){}
  end

  def argument_test(state, proc, *args)
    x = state
    begin
      proc.call(*args)
    rescue ArgumentError
      x = !x
    end
    assert(x,2)
  end

  def test_argument
    argument_test(true, lambda{||})
    argument_test(false, lambda{||}, 1)
    argument_test(true, lambda{|a,|}, 1)
    argument_test(false, lambda{|a,|})
    argument_test(false, lambda{|a,|}, 1,2)
  end

  def get_block(&block)
    block
  end

  def test_get_block
    assert(Proc == get_block{}.class)
    argument_test(true, get_block{||})
    argument_test(true, get_block{||}, 1)
    argument_test(true, get_block{|a,|}, 1)
    argument_test(true, get_block{|a,|})
    argument_test(true, get_block{|a,|}, 1,2)

    argument_test(true, get_block(&lambda{||}))
    argument_test(false, get_block(&lambda{||}),1)
    argument_test(true, get_block(&lambda{|a,|}),1)
    argument_test(false, get_block(&lambda{|a,|}),1,2)

    block = get_block{11}
    assert(block.class == Proc)
    assert(block.to_proc.class == Proc)
    assert(block.clone.call == 11)
    assert(get_block(&block).class == Proc)

    lambda = lambda{44}
    assert(lambda.class == Proc)
    assert(lambda.to_proc.class == Proc)
    assert(lambda.clone.call == 44)
    assert(get_block(&lambda).class == Proc)

    assert(Proc.new{|a,| a}.call(1,2,3) == 1)
    argument_test(true, Proc.new{|a,|}, 1,2)
  end

  def return1_test	# !! test_return1 -> return1_test
    Proc.new {
      return 55
    }.call + 5
  end

  def test_return1
    assert(return1_test() == 55)
  end

  def return2_test	# !! test_return2 -> return2_test
    lambda {
      return 55
    }.call + 5
  end

  def test_return2
    assert(return2_test() == 60)
  end

  def proc_call(&b)
    b.call
  end
  def proc_yield()
    yield
  end
  def proc_return1
    proc_call{return 42}+1
  end

  def test_proc_return1
    assert(proc_return1() == 42)
  end

  def proc_return2
    proc_yield{return 42}+1
  end

  def test_proc_return2
    assert(proc_return2() == 42)
  end

  def ljump_test(state, proc, *args)
    x = state
    begin
      proc.call(*args)
    rescue LocalJumpError
      x = !x
    end
    assert(x,2)
  end

  def test_ljump
    block = get_block{11}
    lambda = lambda{44}
    # ljump_test(false, get_block{break})	# !! This line terminates testrunner...  please sombody fix it.
    ljump_test(true, lambda{break})

    assert(block.arity == -1)
    assert(lambda.arity == -1)
    assert(lambda{||}.arity == 0)
    assert(lambda{|a|}.arity == 1)
    assert(lambda{|a,|}.arity == 1)
    assert(lambda{|a,b|}.arity == 2)
  end

  def marity_test(m)
    method = method(m)
    assert(method.arity == method.to_proc.arity)
  end

  def test_marity
    marity_test(:assert)
    marity_test(:marity_test)
    marity_test(:p)

    lambda(&method(:assert)).call(true)
    lambda(&get_block{|a,n| assert(a,n)}).call(true, 2)
  end

  class ITER_TEST1
    def a
      block_given?
    end
  end

  class ITER_TEST2 < ITER_TEST1
    include Test::Unit::Assertions
    def a
      assert(super)
      super
    end
  end

  def test_iter_test2
    assert(ITER_TEST2.new.a {})
  end

  class ITER_TEST3
    def foo x
      return yield if block_given?
      x
    end
  end

  class ITER_TEST4 < ITER_TEST3
    include Test::Unit::Assertions
    def foo x
      assert(super == yield)
      assert(super(x, &nil) == x)
    end
  end

  def test_iter4
    ITER_TEST4.new.foo(44){55}   
  end
end
