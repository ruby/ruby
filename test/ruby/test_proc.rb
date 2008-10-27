require 'test/unit'

class TestProc < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_proc
    p1 = proc{|i| i}
    assert_equal(2, p1.call(2))
    assert_equal(3, p1.call(3))

    p1 = proc{|i| i*2}
    assert_equal(4, p1.call(2))
    assert_equal(6, p1.call(3))

    p2 = nil
    x=0

    proc{
      iii=5				# nested local variable
      p1 = proc{|i|
        iii = i
      }
      p2 = proc {
        x = iii                 	# nested variables shared by procs
      }
      # scope of nested variables
      assert(defined?(iii))
    }.call
    assert(!defined?(iii))		# out of scope

    loop{iii=5; assert(eval("defined? iii")); break}
    loop {
      iii = 10
      def self.dyna_var_check
        loop {
          assert(!defined?(iii))
          break
        }
      end
      dyna_var_check
      break
    }
    p1.call(5)
    p2.call
    assert_equal(5, x)
  end

  def assert_arity(n)
    meta = class << self; self; end
    meta.class_eval {define_method(:foo, Proc.new)}
    assert_equal(n, method(:foo).arity)
  end

  def test_arity
    assert_equal(0, proc{}.arity)
    assert_equal(0, proc{||}.arity)
    assert_equal(1, proc{|x|}.arity)
    assert_equal(2, proc{|x, y|}.arity)
    assert_equal(-2, proc{|x, *y|}.arity)
    assert_equal(-1, proc{|*x|}.arity)
    assert_equal(-1, proc{|*|}.arity)
    assert_equal(-3, proc{|x, *y, z|}.arity)
    assert_equal(-4, proc{|x, *y, z, a|}.arity)

    assert_arity(0) {}
    assert_arity(0) {||}
    assert_arity(1) {|x|}
    assert_arity(2) {|x, y|}
    assert_arity(-2) {|x, *y|}
    assert_arity(-3) {|x, *y, z|}
    assert_arity(-1) {|*x|}
    assert_arity(-1) {|*|}
  end

  def m(x)
    lambda { x }
  end

  def test_eq
    a = m(1)
    b = m(2)
    assert_not_equal(a, b, "[ruby-dev:22592]")
    assert_not_equal(a.call, b.call, "[ruby-dev:22592]")

    assert_not_equal(proc {||}, proc {|x,y|}, "[ruby-dev:22599]")

    a = lambda {|x| lambda {} }.call(1)
    b = lambda {}
    assert_not_equal(a, b, "[ruby-dev:22601]")
  end

  def test_block_par
    assert_equal(10, Proc.new{|&b| b.call(10)}.call {|x| x})
    assert_equal(12, Proc.new{|a,&b| b.call(a)}.call(12) {|x| x})
  end

  def test_safe
    safe = $SAFE
    c = Class.new
    x = c.new

    p = proc {
      $SAFE += 1
      proc {$SAFE}
    }.call
    assert_equal(safe, $SAFE)
    assert_equal(safe + 1, p.call)
    assert_equal(safe, $SAFE)

    c.class_eval {define_method(:safe, p)}
    assert_equal(safe, x.safe)
    assert_equal(safe, x.method(:safe).call)
    assert_equal(safe, x.method(:safe).to_proc.call)

    p = proc {$SAFE += 1}
    assert_equal(safe + 1, p.call)
    assert_equal(safe, $SAFE)

    c.class_eval {define_method(:inc, p)}
    assert_equal(safe + 1, proc {x.inc; $SAFE}.call)
    assert_equal(safe, $SAFE)
    assert_equal(safe + 1, proc {x.method(:inc).call; $SAFE}.call)
    assert_equal(safe, $SAFE)
    assert_equal(safe + 1, proc {x.method(:inc).to_proc.call; $SAFE}.call)
    assert_equal(safe, $SAFE)
  end

  def m2
    "OK"
  end

  def block
    method(:m2).to_proc
  end

  # [yarv-dev:777] block made by Method#to_proc
  def test_method_to_proc
    b = block()
    assert_equal "OK", b.call
  end

  def test_curry
    b = proc {|x, y, z| (x||0) + (y||0) + (z||0) }
    assert_equal(6, b.curry[1][2][3])
    assert_equal(6, b.curry[1, 2][3, 4])
    assert_equal(6, b.curry(5)[1][2][3][4][5])
    assert_equal(6, b.curry(5)[1, 2][3, 4][5])
    assert_equal(1, b.curry(1)[1])

    b = proc {|x, y, z, *w| (x||0) + (y||0) + (z||0) + w.inject(0, &:+) }
    assert_equal(6, b.curry[1][2][3])
    assert_equal(10, b.curry[1, 2][3, 4])
    assert_equal(15, b.curry(5)[1][2][3][4][5])
    assert_equal(15, b.curry(5)[1, 2][3, 4][5])
    assert_equal(1, b.curry(1)[1])

    b = lambda {|x, y, z| (x||0) + (y||0) + (z||0) }
    assert_equal(6, b.curry[1][2][3])
    assert_raise(ArgumentError) { b.curry[1, 2][3, 4] }
    assert_raise(ArgumentError) { b.curry(5) }
    assert_raise(ArgumentError) { b.curry(1) }

    b = lambda {|x, y, z, *w| (x||0) + (y||0) + (z||0) + w.inject(0, &:+) }
    assert_equal(6, b.curry[1][2][3])
    assert_equal(10, b.curry[1, 2][3, 4])
    assert_equal(15, b.curry(5)[1][2][3][4][5])
    assert_equal(15, b.curry(5)[1, 2][3, 4][5])
    assert_raise(ArgumentError) { b.curry(1) }

    b = proc { :foo }
    assert_equal(:foo, b.curry[])
  end
 
  def test_curry_ski_fib
    s = proc {|f, g, x| f[x][g[x]] }.curry
    k = proc {|x, y| x }.curry
    i = proc {|x| x }.curry

    fib = []
    inc = proc {|x| fib[-1] += 1; x }.curry
    ret = proc {|x| throw :end if fib.size > 10; fib << 0; x }.curry

    catch(:end) do
      s[
        s[s[i][i]][k[i]]
      ][
        k[inc]
      ][
        s[
          s[
            k[s]
          ][
            s[k[s[k[s]]]
          ][
            s[s[k[s]][s[k[s[k[ret]]]][s[k[s[i]]][k]]]][k]]
          ]
        ][
          k[s[k[s]][k]]
        ]
      ]
    end

    assert_equal(fib, [1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89])
  end

  def test_curry_from_knownbug
    a = lambda {|x, y, &b| b }
    b = a.curry[1]

    assert_equal(:ok,
      if b.call(2){} == nil
        :ng
      else
        :ok
      end, 'moved from btest/knownbug, [ruby-core:15551]')
  end

  def test_dup_clone
    b = proc {|x| x + "bar" }
    class << b; attr_accessor :foo; end

    bd = b.dup
    assert_equal("foobar", bd.call("foo"))
    assert_raise(NoMethodError) { bd.foo = :foo }
    assert_raise(NoMethodError) { bd.foo }

    bc = b.clone
    assert_equal("foobar", bc.call("foo"))
    bc.foo = :foo
    assert_equal(:foo, bc.foo)
  end

  def test_binding
    b = proc {|x, y, z| proc {}.binding }.call(1, 2, 3)
    class << b; attr_accessor :foo; end

    bd = b.dup
    assert_equal([1, 2, 3], bd.eval("[x, y, z]"))
    assert_raise(NoMethodError) { bd.foo = :foo }
    assert_raise(NoMethodError) { bd.foo }

    bc = b.clone
    assert_equal([1, 2, 3], bc.eval("[x, y, z]"))
    bc.foo = :foo
    assert_equal(:foo, bc.foo)

    b = nil
    1.times { x, y, z = 1, 2, 3; b = binding }
    assert_equal([1, 2, 3], b.eval("[x, y, z]"))
  end

  def test_proc_lambda
    assert_raise(ArgumentError) { proc }
    assert_raise(ArgumentError) { lambda }

    o = Object.new
    def o.foo
      b = nil
      1.times { b = lambda }
      b
    end
    assert_equal(:foo, o.foo { :foo }.call)

    def o.foo(&b)
      b = nil
      1.times { b = lambda }
      b
    end
    assert_equal(:foo, o.foo { :foo }.call)
  end

  def test_arity2
    assert_equal(0, method(:proc).to_proc.arity)
    assert_equal(-1, proc {}.curry.arity)
  end

  def test_proc_location
    t = Thread.new { sleep }
    assert_raise(ThreadError) { t.instance_eval { initialize { } } }
    t.kill
  end

  def test_eq2
    b1 = proc { }
    b2 = b1.dup
    assert(b1 == b2)
  end
  
  def test_to_proc
    b = proc { :foo }
    assert_equal(:foo, b.to_proc.call)
  end

  def test_localjump_error
    o = Object.new
    def foo; yield; end
    exc = foo rescue $!
    assert_nil(exc.exit_value)
    assert_equal(:noreason, exc.reason)
  end

  def test_binding2
    assert_raise(ArgumentError) { proc {}.curry.binding }
  end

  def test_proc_args_plain
    pr = proc {|a,b,c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil,nil,nil,nil,nil],  pr.call()
    assert_equal [1,nil,nil,nil,nil],  pr.call(1)
    assert_equal [1,2,nil,nil,nil],  pr.call(1,2)
    assert_equal [1,2,3,nil,nil],  pr.call(1,2,3)
    assert_equal [1,2,3,4,nil],  pr.call(1,2,3,4)
    assert_equal [1,2,3,4,5],  pr.call(1,2,3,4,5)
    assert_equal [1,2,3,4,5],  pr.call(1,2,3,4,5,6)

    assert_equal [nil,nil,nil,nil,nil],  pr.call([])
    assert_equal [1,nil,nil,nil,nil],  pr.call([1])
    assert_equal [1,2,nil,nil,nil],  pr.call([1,2])
    assert_equal [1,2,3,nil,nil],  pr.call([1,2,3])
    assert_equal [1,2,3,4,nil],  pr.call([1,2,3,4])
    assert_equal [1,2,3,4,5],  pr.call([1,2,3,4,5])
    assert_equal [1,2,3,4,5],  pr.call([1,2,3,4,5,6])

    r = proc{|a| a}.call([1,2,3])
    assert_equal [1,2,3], r

    r = proc{|a,| a}.call([1,2,3])
    assert_equal 1, r

    r = proc{|a,| a}.call([])
    assert_equal nil, r
  end


  def test_proc_args_rest
    pr = proc {|a,b,c,*d|
      [a,b,c,d]
    }
    assert_equal [nil,nil,nil,[]],  pr.call()
    assert_equal [1,nil,nil,[]],  pr.call(1)
    assert_equal [1,2,nil,[]],  pr.call(1,2)
    assert_equal [1,2,3,[]],  pr.call(1,2,3)
    assert_equal [1,2,3,[4]], pr.call(1,2,3,4)
    assert_equal [1,2,3,[4,5]], pr.call(1,2,3,4,5)
    assert_equal [1,2,3,[4,5,6]], pr.call(1,2,3,4,5,6)

    assert_equal [nil,nil,nil,[]],  pr.call([])
    assert_equal [1,nil,nil,[]],  pr.call([1])
    assert_equal [1,2,nil,[]],  pr.call([1,2])
    assert_equal [1,2,3,[]],  pr.call([1,2,3])
    assert_equal [1,2,3,[4]], pr.call([1,2,3,4])
    assert_equal [1,2,3,[4,5]], pr.call([1,2,3,4,5])
    assert_equal [1,2,3,[4,5,6]], pr.call([1,2,3,4,5,6])

    r = proc{|*a| a}.call([1,2,3])
    assert [1,2,3], r
  end

  def test_proc_args_rest_and_post
    pr = proc {|a,b,*c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil, nil, [], nil, nil], pr.call()
    assert_equal [1, nil, [], nil, nil], pr.call(1)
    assert_equal [1, 2, [], nil, nil], pr.call(1,2)
    assert_equal [1, 2, [], 3, nil], pr.call(1,2,3)
    assert_equal [1, 2, [], 3, 4], pr.call(1,2,3,4)
    assert_equal [1, 2, [3], 4, 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, [3, 4], 5, 6], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, [3, 4, 5], 6,7], pr.call(1,2,3,4,5,6,7)

    assert_equal [nil, nil, [], nil, nil], pr.call([])
    assert_equal [1, nil, [], nil, nil], pr.call([1])
    assert_equal [1, 2, [], nil, nil], pr.call([1,2])
    assert_equal [1, 2, [], 3, nil], pr.call([1,2,3])
    assert_equal [1, 2, [], 3, 4], pr.call([1,2,3,4])
    assert_equal [1, 2, [3], 4, 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, [3, 4], 5, 6], pr.call([1,2,3,4,5,6])
    assert_equal [1, 2, [3, 4, 5], 6,7], pr.call([1,2,3,4,5,6,7])
  end

  def test_proc_args_opt
    pr = proc {|a,b,c=:c|
      [a,b,c]
    }
    assert_equal [nil, nil, :c], pr.call()
    assert_equal [1, nil, :c], pr.call(1)
    assert_equal [1, 2, :c], pr.call(1,2)
    assert_equal [1, 2, 3], pr.call(1,2,3)
    assert_equal [1, 2, 3], pr.call(1,2,3,4)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c], pr.call([])
    assert_equal [1, nil, :c], pr.call([1])
    assert_equal [1, 2, :c], pr.call([1,2])
    assert_equal [1, 2, 3], pr.call([1,2,3])
    assert_equal [1, 2, 3], pr.call([1,2,3,4])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_opt_and_post
    pr = proc {|a,b,c=:c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil, nil, :c, nil, nil], pr.call()
    assert_equal [1, nil, :c, nil, nil], pr.call(1)
    assert_equal [1, 2, :c, nil, nil], pr.call(1,2)
    assert_equal [1, 2, :c, 3, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, 3, 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c, nil, nil], pr.call([])
    assert_equal [1, nil, :c, nil, nil], pr.call([1])
    assert_equal [1, 2, :c, nil, nil], pr.call([1,2])
    assert_equal [1, 2, :c, 3, nil], pr.call([1,2,3])
    assert_equal [1, 2, :c, 3, 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_opt_and_rest
    pr = proc {|a,b,c=:c,*d|
      [a,b,c,d]
    }
    assert_equal [nil, nil, :c, []], pr.call()
    assert_equal [1, nil, :c, []], pr.call(1)
    assert_equal [1, 2, :c, []], pr.call(1,2)
    assert_equal [1, 2, 3, []], pr.call(1,2,3)
    assert_equal [1, 2, 3, [4]], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4, 5]], pr.call(1,2,3,4,5)

    assert_equal [nil, nil, :c, []], pr.call([])
    assert_equal [1, nil, :c, []], pr.call([1])
    assert_equal [1, 2, :c, []], pr.call([1,2])
    assert_equal [1, 2, 3, []], pr.call([1,2,3])
    assert_equal [1, 2, 3, [4]], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4, 5]], pr.call([1,2,3,4,5])
  end

  def test_proc_args_opt_and_rest_and_post
    pr = proc {|a,b,c=:c,*d,e|
      [a,b,c,d,e]
    }
    assert_equal [nil, nil, :c, [], nil], pr.call()
    assert_equal [1, nil, :c, [], nil], pr.call(1)
    assert_equal [1, 2, :c, [], nil], pr.call(1,2)
    assert_equal [1, 2, :c, [], 3], pr.call(1,2,3)
    assert_equal [1, 2, 3, [], 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4], 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, [4,5], 6], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c, [], nil], pr.call([])
    assert_equal [1, nil, :c, [], nil], pr.call([1])
    assert_equal [1, 2, :c, [], nil], pr.call([1,2])
    assert_equal [1, 2, :c, [], 3], pr.call([1,2,3])
    assert_equal [1, 2, 3, [], 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4], 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, [4,5], 6], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_unleashed
    r = proc {|a,b=1,*c,d,e|
      [a,b,c,d,e]
    }.call(1,2,3,4,5)
    assert_equal([1,2,[3],4,5], r, "[ruby-core:19485]")
  end
end
