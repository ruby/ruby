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

    loop{iii=iii=5; assert(eval("defined? iii")); break}
    loop {
      iii=iii = 10
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
    assert_equal(0, proc{|x=1|}.arity)
    assert_equal(2, proc{|x, y|}.arity)
    assert_equal(1, proc{|x=0, y|}.arity)
    assert_equal(0, proc{|x=0, y=0|}.arity)
    assert_equal(1, proc{|x, y=0|}.arity)
    assert_equal(-2, proc{|x, *y|}.arity)
    assert_equal(-1, proc{|x=0, *y|}.arity)
    assert_equal(-1, proc{|*x|}.arity)
    assert_equal(-1, proc{|*|}.arity)
    assert_equal(-3, proc{|x, *y, z|}.arity)
    assert_equal(-2, proc{|x=0, *y, z|}.arity)
    assert_equal(2, proc{|(x, y), z|[x,y]}.arity)
    assert_equal(1, proc{|(x, y), z=0|[x,y]}.arity)
    assert_equal(-4, proc{|x, *y, z, a|}.arity)
    assert_equal(0, proc{|**|}.arity)
    assert_equal(0, proc{|**o|}.arity)
    assert_equal(1, proc{|x, **o|}.arity)
    assert_equal(0, proc{|x=0, **o|}.arity)
    assert_equal(1, proc{|x, y=0, **o|}.arity)
    assert_equal(2, proc{|x, y=0, z, **o|}.arity)
    assert_equal(-3, proc{|x, y=0, *z, w, **o|}.arity)

    assert_equal(2, proc{|x, y=0, z, a:1|}.arity)
    assert_equal(3, proc{|x, y=0, z, a:|}.arity)
    assert_equal(-4, proc{|x, y, *rest, a:, b:, c:|}.arity)
    assert_equal(3, proc{|x, y=0, z, a:, **o|}.arity)

    assert_equal(0, lambda{}.arity)
    assert_equal(0, lambda{||}.arity)
    assert_equal(1, lambda{|x|}.arity)
    assert_equal(-1, lambda{|x=1|}.arity) # different from proc
    assert_equal(2, lambda{|x, y|}.arity)
    assert_equal(-2, lambda{|x=0, y|}.arity) # different from proc
    assert_equal(-1, lambda{|x=0, y=0|}.arity) # different from proc
    assert_equal(-2, lambda{|x, y=0|}.arity) # different from proc
    assert_equal(-2, lambda{|x, *y|}.arity)
    assert_equal(-1, lambda{|x=0, *y|}.arity)
    assert_equal(-1, lambda{|*x|}.arity)
    assert_equal(-1, lambda{|*|}.arity)
    assert_equal(-3, lambda{|x, *y, z|}.arity)
    assert_equal(-2, lambda{|x=0, *y, z|}.arity)
    assert_equal(2, lambda{|(x, y), z|[x,y]}.arity)
    assert_equal(-2, lambda{|(x, y), z=0|[x,y]}.arity)
    assert_equal(-4, lambda{|x, *y, z, a|}.arity)
    assert_equal(-1, lambda{|**|}.arity)
    assert_equal(-1, lambda{|**o|}.arity)
    assert_equal(-2, lambda{|x, **o|}.arity)
    assert_equal(-1, lambda{|x=0, **o|}.arity)
    assert_equal(-2, lambda{|x, y=0, **o|}.arity)
    assert_equal(-3, lambda{|x, y=0, z, **o|}.arity)
    assert_equal(-3, lambda{|x, y=0, *z, w, **o|}.arity)

    assert_arity(0) {}
    assert_arity(0) {||}
    assert_arity(1) {|x|}
    assert_arity(2) {|x, y|}
    assert_arity(-2) {|x, *y|}
    assert_arity(-3) {|x, *y, z|}
    assert_arity(-1) {|*x|}
    assert_arity(-1) {|*|}
    assert_arity(-1) {|**o|}
    assert_arity(-1) {|**|}
    assert_arity(-2) {|x, *y, **|}
    assert_arity(-3) {|x, *y, z, **|}
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

  def m1(var)
    var
  end

  def m_block_given?
    m1(block_given?)
  end

  # [yarv-dev:777] block made by Method#to_proc
  def test_method_to_proc
    b = block()
    assert_equal "OK", b.call
    b = b.binding
    assert_instance_of(Binding, b, '[ruby-core:25589]')
    bug10432 = '[ruby-core:65919] [Bug #10432]'
    assert_same(self, b.receiver, bug10432)
    assert_not_send [b, :local_variable_defined?, :value]
    assert_raise(NameError) {
      b.local_variable_get(:value)
    }
    assert_equal 42, b.local_variable_set(:value, 42)
    assert_send [b, :local_variable_defined?, :value]
    assert_equal 42, b.local_variable_get(:value)
  end

  def test_block_given_method
    m = method(:m_block_given?)
    assert(!m.call, "without block")
    assert(m.call {}, "with block")
    assert(!m.call, "without block second")
  end

  def test_block_given_method_to_proc
    bug8341 = '[Bug #8341]'
    m = method(:m_block_given?).to_proc
    assert(!m.call, "#{bug8341} without block")
    assert(m.call {}, "#{bug8341} with block")
    assert(!m.call, "#{bug8341} without block second")
  end

  def test_block_persist_between_calls
    bug8341 = '[Bug #8341]'
    o = Object.new
    def o.m1(top=true)
      if top
        [block_given?, @m.call(false)]
      else
        block_given?
      end
    end
    m = o.method(:m1).to_proc
    o.instance_variable_set(:@m, m)
    assert_equal([true, false], m.call {}, "#{bug8341} nested with block")
    assert_equal([false, false], m.call, "#{bug8341} nested without block")
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

    b = lambda {|x, y, &blk| blk.call(x + y) }.curry
    b = b.call(2) { raise }
    b = b.call(3) {|x| x + 4 }
    assert_equal(9, b)

    l = proc {}
    assert_equal(false, l.lambda?)
    assert_equal(false, l.curry.lambda?, '[ruby-core:24127]')
    l = lambda {}
    assert_equal(true, l.lambda?)
    assert_equal(true, l.curry.lambda?, '[ruby-core:24127]')
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

  def test_curry_instance_exec
    a = lambda { |x, y| [x + y, self] }
    b = a.curry.call(1)
    result = instance_exec 2, &b

    assert_equal(3, result[0])
    assert_equal(self, result[1])
  end

  def test_curry_optional_params
    obj = Object.new
    def obj.foo(a, b=42); end
    assert_raise(ArgumentError) { obj.method(:foo).to_proc.curry(3) }
    assert_raise(ArgumentError) { ->(a, b=42){}.curry(3) }
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
    1.times { x, y, z = 1, 2, 3; [x,y,z]; b = binding }
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

    c = Class.new
    c.class_eval { attr_accessor :foo }
    assert_equal(1, c.new.method(:foo=).to_proc.arity)
  end

  def test_proc_location
    t = Thread.new { sleep }
    assert_raise(ThreadError) { t.instance_eval { initialize { } } }
    t.kill
    t.join
  end

  def test_to_proc
    b = proc { :foo }
    assert_equal(:foo, b.to_proc.call)
  end

  def test_localjump_error
    o = o = Object.new
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
    assert_equal [[1,2,3]], r
  end

  def test_proc_args_pos_rest_post
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

  def test_proc_args_rest_post
    pr = proc {|*a,b,c|
      [a,b,c]
    }
    assert_equal [[], nil, nil], pr.call()
    assert_equal [[], 1, nil], pr.call(1)
    assert_equal [[], 1, 2], pr.call(1,2)
    assert_equal [[1], 2, 3], pr.call(1,2,3)
    assert_equal [[1, 2], 3, 4], pr.call(1,2,3,4)
    assert_equal [[1, 2, 3], 4, 5], pr.call(1,2,3,4,5)
    assert_equal [[1, 2, 3, 4], 5, 6], pr.call(1,2,3,4,5,6)
    assert_equal [[1, 2, 3, 4, 5], 6,7], pr.call(1,2,3,4,5,6,7)

    assert_equal [[], nil, nil], pr.call([])
    assert_equal [[], 1, nil], pr.call([1])
    assert_equal [[], 1, 2], pr.call([1,2])
    assert_equal [[1], 2, 3], pr.call([1,2,3])
    assert_equal [[1, 2], 3, 4], pr.call([1,2,3,4])
    assert_equal [[1, 2, 3], 4, 5], pr.call([1,2,3,4,5])
    assert_equal [[1, 2, 3, 4], 5, 6], pr.call([1,2,3,4,5,6])
    assert_equal [[1, 2, 3, 4, 5], 6,7], pr.call([1,2,3,4,5,6,7])
  end

  def test_proc_args_pos_opt
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

  def test_proc_args_opt
    pr = proc {|a=:a,b=:b,c=:c|
      [a,b,c]
    }
    assert_equal [:a, :b, :c], pr.call()
    assert_equal [1, :b, :c], pr.call(1)
    assert_equal [1, 2, :c], pr.call(1,2)
    assert_equal [1, 2, 3], pr.call(1,2,3)
    assert_equal [1, 2, 3], pr.call(1,2,3,4)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c], pr.call([])
    assert_equal [1, :b, :c], pr.call([1])
    assert_equal [1, 2, :c], pr.call([1,2])
    assert_equal [1, 2, 3], pr.call([1,2,3])
    assert_equal [1, 2, 3], pr.call([1,2,3,4])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_opt_single
    bug7621 = '[ruby-dev:46801]'
    pr = proc {|a=:a|
      a
    }
    assert_equal :a, pr.call()
    assert_equal 1, pr.call(1)
    assert_equal 1, pr.call(1,2)

    assert_equal [], pr.call([]), bug7621
    assert_equal [1], pr.call([1]), bug7621
    assert_equal [1, 2], pr.call([1,2]), bug7621
    assert_equal [1, 2, 3], pr.call([1,2,3]), bug7621
    assert_equal [1, 2, 3, 4], pr.call([1,2,3,4]), bug7621
  end

  def test_proc_args_pos_opt_post
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

  def test_proc_args_opt_post
    pr = proc {|a=:a,b=:b,c=:c,d,e|
      [a,b,c,d,e]
    }
    assert_equal [:a, :b, :c, nil, nil], pr.call()
    assert_equal [:a, :b, :c, 1, nil], pr.call(1)
    assert_equal [:a, :b, :c, 1, 2], pr.call(1,2)
    assert_equal [1, :b, :c, 2, 3], pr.call(1,2,3)
    assert_equal [1, 2, :c, 3, 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c, nil, nil], pr.call([])
    assert_equal [:a, :b, :c, 1, nil], pr.call([1])
    assert_equal [:a, :b, :c, 1, 2], pr.call([1,2])
    assert_equal [1, :b, :c, 2, 3], pr.call([1,2,3])
    assert_equal [1, 2, :c, 3, 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, 4, 5], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_pos_opt_rest
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

  def test_proc_args_opt_rest
    pr = proc {|a=:a,b=:b,c=:c,*d|
      [a,b,c,d]
    }
    assert_equal [:a, :b, :c, []], pr.call()
    assert_equal [1, :b, :c, []], pr.call(1)
    assert_equal [1, 2, :c, []], pr.call(1,2)
    assert_equal [1, 2, 3, []], pr.call(1,2,3)
    assert_equal [1, 2, 3, [4]], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4, 5]], pr.call(1,2,3,4,5)

    assert_equal [:a, :b, :c, []], pr.call([])
    assert_equal [1, :b, :c, []], pr.call([1])
    assert_equal [1, 2, :c, []], pr.call([1,2])
    assert_equal [1, 2, 3, []], pr.call([1,2,3])
    assert_equal [1, 2, 3, [4]], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4, 5]], pr.call([1,2,3,4,5])
  end

  def test_proc_args_pos_opt_rest_post
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

  def test_proc_args_opt_rest_post
    pr = proc {|a=:a,b=:b,c=:c,*d,e|
      [a,b,c,d,e]
    }
    assert_equal [:a, :b, :c, [], nil], pr.call()
    assert_equal [:a, :b, :c, [], 1], pr.call(1)
    assert_equal [1, :b, :c, [], 2], pr.call(1,2)
    assert_equal [1, 2, :c, [], 3], pr.call(1,2,3)
    assert_equal [1, 2, 3, [], 4], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, [4], 5], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, [4,5], 6], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c, [], nil], pr.call([])
    assert_equal [:a, :b, :c, [], 1], pr.call([1])
    assert_equal [1, :b, :c, [], 2], pr.call([1,2])
    assert_equal [1, 2, :c, [], 3], pr.call([1,2,3])
    assert_equal [1, 2, 3, [], 4], pr.call([1,2,3,4])
    assert_equal [1, 2, 3, [4], 5], pr.call([1,2,3,4,5])
    assert_equal [1, 2, 3, [4,5], 6], pr.call([1,2,3,4,5,6])
  end

  def test_proc_args_pos_block
    pr = proc {|a,b,&c|
      [a, b, c.class, c&&c.call(:x)]
    }
    assert_equal [nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, NilClass, nil], pr.call(1,2,3,4)

    assert_equal [nil, nil, NilClass, nil], pr.call([])
    assert_equal [1, nil, NilClass, nil], pr.call([1])
    assert_equal [1, 2, NilClass, nil], pr.call([1,2])
    assert_equal [1, 2, NilClass, nil], pr.call([1,2,3])
    assert_equal [1, 2, NilClass, nil], pr.call([1,2,3,4])

    assert_equal [nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })

    assert_equal [nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
  end

  def test_proc_args_pos_rest_block
    pr = proc {|a,b,*c,&d|
      [a, b, c, d.class, d&&d.call(:x)]
    }
    assert_equal [nil, nil, [], NilClass, nil], pr.call()
    assert_equal [1, nil, [], NilClass, nil], pr.call(1)
    assert_equal [1, 2, [], NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, [3], NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, [3,4], NilClass, nil], pr.call(1,2,3,4)

    assert_equal [nil, nil, [], Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, [], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, [], Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, [3], Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, [3,4], Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })

    assert_equal [nil, nil, [], Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, [], Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, [], Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, [3], Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, [3,4], Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
  end

  def test_proc_args_rest_block
    pr = proc {|*c,&d|
      [c, d.class, d&&d.call(:x)]
    }
    assert_equal [[], NilClass, nil], pr.call()
    assert_equal [[1], NilClass, nil], pr.call(1)
    assert_equal [[1, 2], NilClass, nil], pr.call(1,2)

    assert_equal [[], Proc, :proc], (pr.call(){ :proc })
    assert_equal [[1], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [[1, 2], Proc, :proc], (pr.call(1, 2){ :proc })

    assert_equal [[], Proc, :x], (pr.call(){|x| x})
    assert_equal [[1], Proc, :x], (pr.call(1){|x| x})
    assert_equal [[1, 2], Proc, :x], (pr.call(1, 2){|x| x})
  end

  def test_proc_args_pos_rest_post_block
    pr = proc {|a,b,*c,d,e,&f|
      [a, b, c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [nil, nil, [], nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, [], nil, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, [], nil, nil, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, [], 3, nil, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, [], 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, [3], 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, [3,4], 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, [], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, [], nil, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, [], nil, nil, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, [], 3, nil, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, [], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, [3], 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, [3,4], 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })

    assert_equal [nil, nil, [], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, [], nil, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, [], nil, nil, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, [], 3, nil, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, [], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, [3], 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, [3,4], 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
  end

  def test_proc_args_rest_post_block
    pr = proc {|*c,d,e,&f|
      [c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [[], nil, nil, NilClass, nil], pr.call()
    assert_equal [[], 1, nil, NilClass, nil], pr.call(1)
    assert_equal [[], 1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [[1], 2, 3, NilClass, nil], pr.call(1,2,3)
    assert_equal [[1, 2], 3, 4, NilClass, nil], pr.call(1,2,3,4)

    assert_equal [[], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [[], 1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [[], 1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [[1], 2, 3, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [[1, 2], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })

    assert_equal [[], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [[], 1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [[], 1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [[1], 2, 3, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [[1, 2], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
  end

  def test_proc_args_pos_opt_block
    pr = proc {|a,b,c=:c,d=:d,&e|
      [a, b, c, d, e.class, e&&e.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4,5)

    assert_equal [nil, nil, :c, :d, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })

    assert_equal [nil, nil, :c, :d, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
  end

  def test_proc_args_opt_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,&e|
      [a, b, c, d, e.class, e&&e.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, NilClass, nil], pr.call()
    assert_equal [1, :b, :c, :d, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, NilClass, nil], pr.call(1,2,3,4,5)

    assert_equal [:a, :b, :c, :d, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, :b, :c, :d, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })

    assert_equal [:a, :b, :c, :d, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, :b, :c, :d, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
  end

  def test_proc_args_pos_opt_post_block
    pr = proc {|a,b,c=:c,d=:d,e,f,&g|
      [a, b, c, d, e, f, g.class, g&&g.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, nil, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, nil, nil, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, :c, :d, 3, nil, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6,7)

    assert_equal [nil, nil, :c, :d, nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, nil, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, nil, nil, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, :c, :d, 3, nil, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })

    assert_equal [nil, nil, :c, :d, nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, nil, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, nil, nil, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, :c, :d, 3, nil, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
  end

  def test_proc_args_opt_post_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,e,f,&g|
      [a, b, c, d, e, f, g.class, g&&g.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, nil, nil, NilClass, nil], pr.call()
    assert_equal [:a, :b, :c, :d, 1, nil, NilClass, nil], pr.call(1)
    assert_equal [:a, :b, :c, :d, 1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [1, :b, :c, :d, 2, 3, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6,7)

    assert_equal [:a, :b, :c, :d, nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [:a, :b, :c, :d, 1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [:a, :b, :c, :d, 1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, :b, :c, :d, 2, 3, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })

    assert_equal [:a, :b, :c, :d, nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [:a, :b, :c, :d, 1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [:a, :b, :c, :d, 1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, :b, :c, :d, 2, 3, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
  end

  def test_proc_args_pos_opt_rest_block
    pr = proc {|a,b,c=:c,d=:d,*e,&f|
      [a, b, c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, [], NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, [], NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, [], NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, [], NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, [], NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, [5], NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [5,6], NilClass, nil], pr.call(1,2,3,4,5,6)

    assert_equal [nil, nil, :c, :d, [], Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, [], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, [], Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, [], Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, [], Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, [5], Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })

    assert_equal [nil, nil, :c, :d, [], Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, [], Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, [], Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, [], Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, [], Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, [5], Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
  end

  def test_proc_args_opt_rest_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,*e,&f|
      [a, b, c, d, e, f.class, f&&f.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, [], NilClass, nil], pr.call()
    assert_equal [1, :b, :c, :d, [], NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, [], NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, 3, :d, [], NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, 3, 4, [], NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, 4, [5], NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [5,6], NilClass, nil], pr.call(1,2,3,4,5,6)

    assert_equal [:a, :b, :c, :d, [], Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, :b, :c, :d, [], Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, [], Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, 3, :d, [], Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, 3, 4, [], Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, 4, [5], Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })

    assert_equal [:a, :b, :c, :d, [], Proc, :x], (pr.call(){|x| x})
    assert_equal [1, :b, :c, :d, [], Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, [], Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, 3, :d, [], Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, 3, 4, [], Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, 4, [5], Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
  end

  def test_proc_args_pos_opt_rest_post_block
    pr = proc {|a,b,c=:c,d=:d,*e,f,g,&h|
      [a, b, c, d, e, f, g, h.class, h&&h.call(:x)]
    }
    assert_equal [nil, nil, :c, :d, [], nil, nil, NilClass, nil], pr.call()
    assert_equal [1, nil, :c, :d, [], nil, nil, NilClass, nil], pr.call(1)
    assert_equal [1, 2, :c, :d, [], nil, nil, NilClass, nil], pr.call(1,2)
    assert_equal [1, 2, :c, :d, [], 3, nil, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, [], 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, [], 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [], 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, [5], 6, 7, NilClass, nil], pr.call(1,2,3,4,5,6,7)
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, NilClass, nil], pr.call(1,2,3,4,5,6,7,8)

    assert_equal [nil, nil, :c, :d, [], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [1, nil, :c, :d, [], nil, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [1, 2, :c, :d, [], nil, nil, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, 2, :c, :d, [], 3, nil, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){ :proc })

    assert_equal [nil, nil, :c, :d, [], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [1, nil, :c, :d, [], nil, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [1, 2, :c, :d, [], nil, nil, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, 2, :c, :d, [], 3, nil, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){|x| x})
  end

  def test_proc_args_opt_rest_post_block
    pr = proc {|a=:a,b=:b,c=:c,d=:d,*e,f,g,&h|
      [a, b, c, d, e, f, g, h.class, h&&h.call(:x)]
    }
    assert_equal [:a, :b, :c, :d, [], nil, nil, NilClass, nil], pr.call()
    assert_equal [:a, :b, :c, :d, [], 1, nil, NilClass, nil], pr.call(1)
    assert_equal [:a, :b, :c, :d, [], 1, 2, NilClass, nil], pr.call(1,2)
    assert_equal [1, :b, :c, :d, [], 2, 3, NilClass, nil], pr.call(1,2,3)
    assert_equal [1, 2, :c, :d, [], 3, 4, NilClass, nil], pr.call(1,2,3,4)
    assert_equal [1, 2, 3, :d, [], 4, 5, NilClass, nil], pr.call(1,2,3,4,5)
    assert_equal [1, 2, 3, 4, [], 5, 6, NilClass, nil], pr.call(1,2,3,4,5,6)
    assert_equal [1, 2, 3, 4, [5], 6, 7, NilClass, nil], pr.call(1,2,3,4,5,6,7)
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, NilClass, nil], pr.call(1,2,3,4,5,6,7,8)

    assert_equal [:a, :b, :c, :d, [], nil, nil, Proc, :proc], (pr.call(){ :proc })
    assert_equal [:a, :b, :c, :d, [], 1, nil, Proc, :proc], (pr.call(1){ :proc })
    assert_equal [:a, :b, :c, :d, [], 1, 2, Proc, :proc], (pr.call(1, 2){ :proc })
    assert_equal [1, :b, :c, :d, [], 2, 3, Proc, :proc], (pr.call(1, 2, 3){ :proc })
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :proc], (pr.call(1, 2, 3, 4){ :proc })
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :proc], (pr.call(1, 2, 3, 4, 5){ :proc })
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6){ :proc })
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7){ :proc })
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :proc], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){ :proc })

    assert_equal [:a, :b, :c, :d, [], nil, nil, Proc, :x], (pr.call(){|x| x})
    assert_equal [:a, :b, :c, :d, [], 1, nil, Proc, :x], (pr.call(1){|x| x})
    assert_equal [:a, :b, :c, :d, [], 1, 2, Proc, :x], (pr.call(1, 2){|x| x})
    assert_equal [1, :b, :c, :d, [], 2, 3, Proc, :x], (pr.call(1, 2, 3){|x| x})
    assert_equal [1, 2, :c, :d, [], 3, 4, Proc, :x], (pr.call(1, 2, 3, 4){|x| x})
    assert_equal [1, 2, 3, :d, [], 4, 5, Proc, :x], (pr.call(1, 2, 3, 4, 5){|x| x})
    assert_equal [1, 2, 3, 4, [], 5, 6, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6){|x| x})
    assert_equal [1, 2, 3, 4, [5], 6, 7, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7){|x| x})
    assert_equal [1, 2, 3, 4, [5,6], 7, 8, Proc, :x], (pr.call(1, 2, 3, 4, 5, 6, 7, 8){|x| x})
  end

  def test_proc_args_pos_unleashed
    r = proc {|a,b=1,*c,d,e|
      [a,b,c,d,e]
    }.call(1,2,3,4,5)
    assert_equal([1,2,[3],4,5], r, "[ruby-core:19485]")
  end

  def test_parameters
    assert_equal([], proc {}.parameters)
    assert_equal([], proc {||}.parameters)
    assert_equal([[:opt, :a]], proc {|a|}.parameters)
    assert_equal([[:opt, :a], [:opt, :b]], proc {|a, b|}.parameters)
    assert_equal([[:opt, :a], [:block, :b]], proc {|a=:a, &b|}.parameters)
    assert_equal([[:opt, :a], [:opt, :b]], proc {|a, b=:b|}.parameters)
    assert_equal([[:rest, :a]], proc {|*a|}.parameters)
    assert_equal([[:opt, :a], [:rest, :b], [:block, :c]], proc {|a, *b, &c|}.parameters)
    assert_equal([[:opt, :a], [:rest, :b], [:opt, :c]], proc {|a, *b, c|}.parameters)
    assert_equal([[:opt, :a], [:rest, :b], [:opt, :c], [:block, :d]], proc {|a, *b, c, &d|}.parameters)
    assert_equal([[:opt, :a], [:opt, :b], [:rest, :c], [:opt, :d], [:block, :e]], proc {|a, b=:b, *c, d, &e|}.parameters)
    assert_equal([[:opt, nil], [:block, :b]], proc {|(a), &b|a}.parameters)
    assert_equal([[:opt, :a], [:opt, :b], [:opt, :c], [:opt, :d], [:rest, :e], [:opt, :f], [:opt, :g], [:block, :h]], proc {|a,b,c=:c,d=:d,*e,f,g,&h|}.parameters)

    assert_equal([[:req]], method(:putc).parameters)
    assert_equal([[:rest]], method(:p).parameters)
  end

  def pm0() end
  def pm1(a) end
  def pm2(a, b) end
  def pmo1(a = :a, &b) end
  def pmo2(a, b = :b) end
  def pmo3(*a) end
  def pmo4(a, *b, &c) end
  def pmo5(a, *b, c) end
  def pmo6(a, *b, c, &d) end
  def pmo7(a, b = :b, *c, d, &e) end
  def pma1((a), &b) a; end
  def pmk1(**) end
  def pmk2(**o) nil && o end
  def pmk3(a, **o) nil && o end
  def pmk4(a = nil, **o) nil && o end
  def pmk5(a, b = nil, **o) nil && o end
  def pmk6(a, b = nil, c, **o) nil && o end
  def pmk7(a, b = nil, *c, d, **o) nil && o end


  def test_bound_parameters
    assert_equal([], method(:pm0).to_proc.parameters)
    assert_equal([[:req, :a]], method(:pm1).to_proc.parameters)
    assert_equal([[:req, :a], [:req, :b]], method(:pm2).to_proc.parameters)
    assert_equal([[:opt, :a], [:block, :b]], method(:pmo1).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b]], method(:pmo2).to_proc.parameters)
    assert_equal([[:rest, :a]], method(:pmo3).to_proc.parameters)
    assert_equal([[:req, :a], [:rest, :b], [:block, :c]], method(:pmo4).to_proc.parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c]], method(:pmo5).to_proc.parameters)
    assert_equal([[:req, :a], [:rest, :b], [:req, :c], [:block, :d]], method(:pmo6).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:block, :e]], method(:pmo7).to_proc.parameters)
    assert_equal([[:req], [:block, :b]], method(:pma1).to_proc.parameters)
    assert_equal([[:keyrest]], method(:pmk1).to_proc.parameters)
    assert_equal([[:keyrest, :o]], method(:pmk2).to_proc.parameters)
    assert_equal([[:req, :a], [:keyrest, :o]], method(:pmk3).to_proc.parameters)
    assert_equal([[:opt, :a], [:keyrest, :o]], method(:pmk4).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:keyrest, :o]], method(:pmk5).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:req, :c], [:keyrest, :o]], method(:pmk6).to_proc.parameters)
    assert_equal([[:req, :a], [:opt, :b], [:rest, :c], [:req, :d], [:keyrest, :o]], method(:pmk7).to_proc.parameters)

    assert_equal([], "".method(:upcase).to_proc.parameters)
    assert_equal([[:rest]], "".method(:gsub).to_proc.parameters)
    assert_equal([[:rest]], proc {}.curry.parameters)
  end

  def test_to_s
    assert_match(/^#<Proc:0x\h+@#{ Regexp.quote(__FILE__) }:\d+>$/, proc {}.to_s)
    assert_match(/^#<Proc:0x\h+@#{ Regexp.quote(__FILE__) }:\d+ \(lambda\)>$/, lambda {}.to_s)
    assert_match(/^#<Proc:0x\h+ \(lambda\)>$/, method(:p).to_proc.to_s)
    x = proc {}
    x.taint
    assert_predicate(x.to_s, :tainted?)
  end

  @@line_of_source_location_test = __LINE__ + 1
  def source_location_test a=1,
    b=2
  end

  def test_source_location
    file, lineno = method(:source_location_test).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_source_location_test, lineno, 'Bug #2427')
  end

  @@line_of_attr_reader_source_location_test   = __LINE__ + 3
  @@line_of_attr_writer_source_location_test   = __LINE__ + 3
  @@line_of_attr_accessor_source_location_test = __LINE__ + 3
  attr_reader   :attr_reader_source_location_test
  attr_writer   :attr_writer_source_location_test
  attr_accessor :attr_accessor_source_location_test

  def test_attr_source_location
    file, lineno = method(:attr_reader_source_location_test).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_reader_source_location_test, lineno)

    file, lineno = method(:attr_writer_source_location_test=).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_writer_source_location_test, lineno)

    file, lineno = method(:attr_accessor_source_location_test).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_accessor_source_location_test, lineno)

    file, lineno = method(:attr_accessor_source_location_test=).source_location
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(@@line_of_attr_accessor_source_location_test, lineno)
  end

  def block_source_location_test(*args, &block)
    block.source_location
  end

  def test_block_source_location
    exp_lineno = __LINE__ + 3
    file, lineno = block_source_location_test(1,
                                              2,
                                              3) do
                                              end
    assert_match(/^#{ Regexp.quote(__FILE__) }$/, file)
    assert_equal(exp_lineno, lineno)
  end

  def test_splat_without_respond_to
    def (obj = Object.new).respond_to?(m,*); false end
    [obj].each do |a, b|
      assert_equal([obj, nil], [a, b], '[ruby-core:24139]')
    end
  end

  def test_curry_with_trace
    # bug3751 = '[ruby-core:31871]'
    set_trace_func(proc {})
    test_curry
  ensure
    set_trace_func(nil)
  end

  def test_block_propagation
    bug3792 = '[ruby-core:32075]'
    c = Class.new do
      def foo
        yield
      end
    end

    o = c.new
    f = :foo.to_proc
    assert_nothing_raised(LocalJumpError, bug3792) {
      assert_equal('bar', f.(o) {'bar'}, bug3792)
    }
    assert_nothing_raised(LocalJumpError, bug3792) {
      assert_equal('zot', o.method(:foo).to_proc.() {'zot'}, bug3792)
    }
  end

  def test_overridden_lambda
    bug8345 = '[ruby-core:54687] [Bug #8345]'
    assert_normal_exit('def lambda; end; method(:puts).to_proc', bug8345)
  end

  def test_overridden_proc
    bug8345 = '[ruby-core:54688] [Bug #8345]'
    assert_normal_exit('def proc; end; ->{}.curry', bug8345)
  end

  def get_binding if: 1, case: 2, when: 3, begin: 4, end: 5
    a ||= 0
    binding
  end

  def test_local_variables
    b = get_binding
    assert_equal(%i'if case when begin end a', b.local_variables)
    a = tap {|;a, b| break binding.local_variables}
    assert_equal(%i[a b], a.sort)
  end

  def test_local_variables_nested
    b = tap {break binding}
    assert_equal(%i[b], b.local_variables, '[ruby-dev:48351] [Bug #10001]')
  end

  def local_variables_of(bind)
    this_should_not_be_in_bind = 2
    bind.local_variables
  end

  def test_local_variables_in_other_context
    feature8773 = '[Feature #8773]'
    assert_equal([:feature8773], local_variables_of(binding), feature8773)
  end

  def test_local_variable_get
    b = get_binding
    assert_equal(0, b.local_variable_get(:a))
    assert_raise(NameError){ b.local_variable_get(:b) }

    # access keyword named local variables
    assert_equal(1, b.local_variable_get(:if))
    assert_equal(2, b.local_variable_get(:case))
    assert_equal(3, b.local_variable_get(:when))
    assert_equal(4, b.local_variable_get(:begin))
    assert_equal(5, b.local_variable_get(:end))
  end

  def test_local_variable_set
    b = get_binding
    b.local_variable_set(:a, 10)
    b.local_variable_set(:b, 20)
    assert_equal(10, b.local_variable_get(:a))
    assert_equal(20, b.local_variable_get(:b))
    assert_equal(10, b.eval("a"))
    assert_equal(20, b.eval("b"))
  end

  def test_local_variable_defined?
    b = get_binding
    assert_equal(true, b.local_variable_defined?(:a))
    assert_equal(false, b.local_variable_defined?(:b))
  end

  def test_binding_receiver
    feature8779 = '[ruby-dev:47613] [Feature #8779]'

    assert_same(self, binding.receiver, feature8779)

    obj = Object.new
    def obj.b; binding; end
    assert_same(obj, obj.b.receiver, feature8779)
  end
end
