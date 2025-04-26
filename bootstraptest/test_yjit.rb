# To run the tests in this file only, with YJIT enabled:
# make btest BTESTS=bootstraptest/test_yjit.rb RUN_OPTS="--yjit-call-threshold=1"

# regression test for popping before side exit
assert_equal "ok", %q{
  def foo(a, *) = a

  def call(args, &)
    foo(1) # spill at where the block arg will be
    foo(*args, &)
  end

  call([1, 2])

  begin
    call([])
  rescue ArgumentError
    :ok
  end
}

# regression test for send processing before side exit
assert_equal "ok", %q{
  def foo(a, *) = :foo

  def call(args)
    send(:foo, *args)
  end

  call([1, 2])

  begin
    call([])
  rescue ArgumentError
    :ok
  end
}

# test discarding extra yield arguments
assert_equal "22131300500015901015", %q{
  def splat_kw(ary) = yield *ary, a: 1

  def splat(ary) = yield *ary

  def kw = yield 1, 2, a: 3

  def kw_only = yield a: 0

  def simple = yield 0, 1

  def none = yield

  def calls
    [
      splat([1, 1, 2]) { |x, y| x + y },
      splat([1, 1, 2]) { |y, opt = raise| opt + y},
      splat_kw([0, 1]) { |a:| a },
      kw { |a:| a },
      kw { |one| one },
      kw { |one, a:| a },
      kw_only { |a:| a },
      kw_only { |a: 1| a },
      simple { 5.itself },
      simple { |a| a },
      simple { |opt = raise| opt },
      simple { |*rest| rest },
      simple { |opt_kw: 5| opt_kw },
      none { |a: 9| a },
      # autosplat ineractions
      [0, 1, 2].yield_self { |a, b| [a, b] },
      [0, 1, 2].yield_self { |a, opt = raise| [a, opt] },
      [1].yield_self { |a, opt = 4| a + opt },
    ]
  end

  calls.join
}

# test autosplat with empty splat
assert_equal "ok", %q{
  def m(pos, splat) = yield pos, *splat

  m([:ok], []) {|v0,| v0 }
}

# regression test for send stack shifting
assert_normal_exit %q{
  def foo(a, b)
    a.singleton_methods(b)
  end

  def call_foo
    [1, 1, 1, 1, 1, 1, send(:foo, 1, 1)]
  end

  call_foo
}

# regression test for keyword splat with yield
assert_equal 'nil', %q{
  def splat_kw(kwargs) = yield(**kwargs)

  splat_kw({}) { _1 }.inspect
}

# regression test for arity check with splat
assert_equal '[:ae, :ae]', %q{
  def req_one(a_, b_ = 1) = raise

  def test(args)
    req_one *args
  rescue ArgumentError
    :ae
  end

  [test(Array.new 5), test([])]
}

# regression test for arity check with splat and send
assert_equal '[:ae, :ae]', %q{
  def two_reqs(a, b_, _ = 1) = a.gsub(a, a)

  def test(name, args)
    send(name, *args)
  rescue ArgumentError
    :ae
  end

  [test(:two_reqs, ["g", nil, nil, nil]), test(:two_reqs, ["g"])]
}

# regression test for GC marking stubs in invalidated code
assert_normal_exit %q{
  skip true unless GC.respond_to?(:compact)
  garbage = Array.new(10_000) { [] } # create garbage to cause iseq movement
  eval(<<~RUBY)
  def foo(n, garbage)
    if n == 2
      # 1.times.each to create a cfunc frame to preserve the JIT frame
      # which will return to a stub housed in an invalidated block
      return 1.times.each do
        Object.define_method(:foo) {}
        garbage.clear
        GC.verify_compaction_references(toward: :empty, expand_heap: true)
      end
    end

    foo(n + 1, garbage)
  end
  RUBY

  foo(1, garbage)
}

# regression test for callee block handler overlapping with arguments
assert_equal '3', %q{
  def foo(_req, *args) = args.last

  def call_foo = foo(0, 1, 2, 3, &->{})

  call_foo
}

# call leaf builtin with a block argument
assert_equal '0', "0.abs(&nil)"

# regression test for invokeblock iseq guard
assert_equal 'ok', %q{
  skip :ok unless GC.respond_to?(:compact)
  def foo = yield
  10.times do |i|
    ret = eval("foo { #{i} }")
    raise "failed at #{i}" unless ret == i
    GC.compact
  end
  :ok
}

# regression test for overly generous guard elision
assert_equal '[0, :sum, 0, :sum]', %q{
  # In faulty versions, the following happens:
  #  1. YJIT puts object on the temp stack with type knowledge
  #     (CArray or CString) about RBASIC_CLASS(object).
  #  2. In iter=0, due to the type knowledge, YJIT generates
  #     a call to sum() without any guard on RBASIC_CLASS(object).
  #  3. In iter=1, a singleton class is added to the object,
  #     changing RBASIC_CLASS(object), falsifying the type knowledge.
  #  4. Because the code from (1) has no class guard, it is incorrectly
  #     reused and the wrong method is invoked.
  # Putting a literal is important for gaining type knowledge.
  def carray(iter)
    array = []
    array.sum(iter.times { def array.sum(_) = :sum })
  end

  def cstring(iter)
    string = "".dup
    string.sum(iter.times { def string.sum(_) = :sum })
  end

  [carray(0), carray(1), cstring(0), cstring(1)]
}

# regression test for return type of Integer#/
# It can return a T_BIGNUM when inputs are T_FIXNUM.
assert_equal 0x3fffffffffffffff.to_s, %q{
  def call(fixnum_min)
    (fixnum_min / -1) - 1
  end

  call(-(2**62))
}

# regression test for return type of String#<<
assert_equal 'Sub', %q{
  def call(sub) = (sub << sub).itself

  class Sub < String; end

  call(Sub.new('o')).class
}

# String#dup with FL_EXIVAR
assert_equal '["str", "ivar"]', %q{
  def str_dup(str) = str.dup
  str = "str"
  str.instance_variable_set(:@ivar, "ivar")
  str = str_dup(str)
  [str, str.instance_variable_get(:@ivar)]
}

# test splat filling required and feeding rest
assert_equal '[0, 1, 2, [3, 4]]', %q{
  public def lead_rest(a, b, *rest)
    [self, a, b, rest]
  end

  def call(args) = 0.lead_rest(*args)

  call([1, 2, 3, 4])
}

# test missing opts are nil initialized
assert_equal '[[0, 1, nil, 3], [0, 1, nil, 3], [0, 1, nil, 3, []], [0, 1, nil, 3, []]]', %q{
  public def lead_opts(a, b=binding.local_variable_get(:c), c=3)
    [self, a, b, c]
  end

  public def opts_rest(a=raise, b=binding.local_variable_get(:c), c=3, *rest)
    [self, a, b, c, rest]
  end

  def call(args)
    [
      0.lead_opts(1),
      0.lead_opts(*args),

      0.opts_rest(1),
      0.opts_rest(*args),
    ]
  end

  call([1])
}

# test filled optionals with unspecified keyword param
assert_equal 'ok', %q{
  def opt_rest_opt_kw(_=1, *, k: :ok) = k

  def call = opt_rest_opt_kw(0)

  call
}

# test splat empty array with rest param
assert_equal '[0, 1, 2, []]', %q{
  public def foo(a=1, b=2, *rest)
    [self, a, b, rest]
  end

  def call(args) = 0.foo(*args)

  call([])
}

# Regression test for yielding with autosplat to block with
# optional parameters. https://github.com/Shopify/yjit/issues/313
assert_equal '[:a, :b, :a, :b]', %q{
  def yielder(arg) = yield(arg) + yield(arg)

  yielder([:a, :b]) do |c = :c, d = :d|
    [c, d]
  end
}

# Regression test for GC mishap while doing shape transition
assert_equal '[:ok]', %q{
  # [Bug #19601]
  class RegressionTest
    def initialize
      @a = @b = @fourth_ivar_does_shape_transition = nil
    end

    def extender
      @first_extended_ivar = [:ok]
    end
  end

  GC.stress = true

  # Used to crash due to GC run in rb_ensure_iv_list_size()
  # not marking the newly allocated [:ok].
  RegressionTest.new.extender.itself
}

assert_equal 'true', %q{
  # regression test for tracking type of locals for too long
  def local_setting_cmp(five)
    victim = 5
    five.define_singleton_method(:respond_to?) do |_, _|
      victim = nil
    end

    # +1 makes YJIT track that victim is a number and
    # defined? calls respond_to? from above indirectly
    unless (victim + 1) && defined?(five.something)
      # Would return wrong result if we still think `five` is a number
      victim.nil?
    end
  end

  local_setting_cmp(Object.new)
  local_setting_cmp(Object.new)
}

assert_equal '18374962167983112447', %q{
  # regression test for incorrectly discarding 32 bits of a pointer when it
  # comes to default values.
  def large_literal_default(n: 0xff00_fabcafe0_00ff)
    n
  end

  def call_graph_root
    large_literal_default
  end

  call_graph_root
  call_graph_root
}

assert_normal_exit %q{
  # regression test for a leak caught by an assert on --yjit-call-threshold=2
  Foo = 1

  eval("def foo = [#{(['Foo,']*256).join}]")

  foo
  foo

  Object.send(:remove_const, :Foo)
}

assert_normal_exit %q{
  # Test to ensure send on overridden c functions
  # doesn't corrupt the stack
  class Bar
    def bar(x)
      x
    end
  end

  class Foo
    def bar
      Bar.new
    end
  end

  foo = Foo.new
  # before this change, this line would error
  # because "s" would still be on the stack
  # String.to_s is the overridden method here
  p foo.bar.bar("s".__send__(:to_s))
}


assert_equal '[nil, nil, nil, nil, nil, nil]', %q{
  [NilClass, TrueClass, FalseClass, Integer, Float, Symbol].each do |klass|
    klass.class_eval("def foo = @foo")
  end

  [nil, true, false, 0xFABCAFE, 0.42, :cake].map do |instance|
    instance.foo
    instance.foo
  end
}

assert_equal '[nil, nil, nil, nil, nil, nil]', %q{
  # Tests defined? on non-heap objects
  [NilClass, TrueClass, FalseClass, Integer, Float, Symbol].each do |klass|
    klass.class_eval("def foo = defined?(@foo)")
  end

  [nil, true, false, 0xFABCAFE, 0.42, :cake].map do |instance|
    instance.foo
    instance.foo
  end
}

assert_equal '[nil, "instance-variable", nil, "instance-variable"]', %q{
  # defined? on object that changes shape between calls
  class Foo
    def foo
      defined?(@foo)
    end

    def add
      @foo = 1
    end

    def remove
      self.remove_instance_variable(:@foo)
    end
  end

  obj = Foo.new
  [obj.foo, (obj.add; obj.foo), (obj.remove; obj.foo), (obj.add; obj.foo)]
}

assert_equal '["instance-variable", 5]', %q{
  # defined? on object too complex for shape information
  class Foo
    def initialize
      100.times { |i| instance_variable_set("@foo#{i}", i) }
    end

    def foo
      [defined?(@foo5), @foo5]
    end
  end

  Foo.new.foo
}

# getinstancevariable with shape too complex
assert_normal_exit %q{
  class Foo
    def initialize
      @a = 1
    end

    def getter
      @foobar
    end
  end

  # Initialize ivars in changing order, making the Foo
  # class have shape too complex
  100.times do |x|
    foo = Foo.new
    foo.instance_variable_set(:"@a#{x}", 1)
    foo.instance_variable_set(:"@foobar", 777)

    # The getter method eventually sees shape too complex
    r = foo.getter
    if r != 777
      raise "error"
    end
  end
}

assert_equal '0', %q{
  # This is a regression test for incomplete invalidation from
  # opt_setinlinecache. This test might be brittle, so
  # feel free to remove it in the future if it's too annoying.
  # This test assumes --yjit-call-threshold=2.
  module M
    Foo = 1
    def foo
      Foo
    end

    def pin_self_type_then_foo
      _ = @foo
      foo
    end

    def only_ints
      1 + self
      foo
    end
  end

  class Integer
    include M
  end

  class Sub
    include M
  end

  foo_method = M.instance_method(:foo)

  dbg = ->(message) do
    return # comment this out to get printouts

    $stderr.puts RubyVM::YJIT.disasm(foo_method)
    $stderr.puts message
  end

  2.times { 42.only_ints }

  dbg["There should be two versions of getinlineache"]

  module M
    remove_const(:Foo)
  end

  dbg["There should be no getinlinecaches"]

  2.times do
    42.only_ints
  rescue NameError => err
    _ = "caught name error #{err}"
  end

  dbg["There should be one version of getinlineache"]

  2.times do
    Sub.new.pin_self_type_then_foo
  rescue NameError
    _ = 'second specialization'
  end

  dbg["There should be two versions of getinlineache"]

  module M
    Foo = 1
  end

  dbg["There should still be two versions of getinlineache"]

  42.only_ints

  dbg["There should be no getinlinecaches"]

  # Find name of the first VM instruction in M#foo.
  insns = RubyVM::InstructionSequence.of(foo_method).to_a
  if defined?(RubyVM::YJIT.blocks_for) && (insns.last.find { Array === _1 }&.first == :opt_getinlinecache)
    RubyVM::YJIT.blocks_for(RubyVM::InstructionSequence.of(foo_method))
      .filter { _1.iseq_start_index == 0 }.count
  else
    0 # skip the test
  end
}

# Check that frozen objects are respected
assert_equal 'great', %q{
  class Foo
    attr_accessor :bar
    def initialize
      @bar = 1
      freeze
    end
  end

  foo = Foo.new

  5.times do
    begin
      foo.bar = 2
    rescue FrozenError
    end
  end

  foo.bar == 1 ? "great" : "NG"
}

# Check that global variable set works
assert_equal 'string', %q{
  def foo
    $foo = "string"
  end

  foo
}

# Check that exceptions work when setting global variables
assert_equal 'rescued', %q{
  def set_var
    $var = 100
  rescue
    :rescued
  end

  set_var
  trace_var(:$var) { raise }
  set_var
}

# Check that global variables work
assert_equal 'string', %q{
  $foo = "string"

  def foo
    $foo
  end

  foo
}

# Check that exceptions work when getting global variable
assert_equal 'rescued', %q{
  Warning[:deprecated] = true

  module Warning
    def warn(message)
      raise
    end
  end

  def get_var
    $=
  rescue
    :rescued
  end

  $VERBOSE = true
  get_var
  get_var
}

# Check that global tracepoints work
assert_equal 'true', %q{
  def foo
    1
  end

  foo
  foo
  foo

  called = false

  tp = TracePoint.new(:return) { |event|
    if event.method_id == :foo
      called = true
    end
  }
  tp.enable
  foo
  tp.disable
  called
}

# Check that local tracepoints work
assert_equal 'true', %q{
  def foo
    1
  end

  foo
  foo
  foo

  called = false

  tp = TracePoint.new(:return) { |_| called = true }
  tp.enable(target: method(:foo))
  foo
  tp.disable
  called
}

# Make sure that optional param methods return the correct value
assert_equal '1', %q{
  def m(ary = [])
    yield(ary)
  end

  # Warm the JIT with a 0 param call
  2.times { m { } }
  m(1) { |v| v }
}

# Test for topn
assert_equal 'array', %q{
  def threequals(a)
    case a
    when Array
      "array"
    when Hash
      "hash"
    else
      "unknown"
    end
  end

  threequals([])
  threequals([])
  threequals([])
}

# Test for opt_mod
assert_equal '2', %q{
  def mod(a, b)
    a % b
  end

  mod(7, 5)
  mod(7, 5)
}

# Test for opt_mult
assert_equal '12', %q{
  def mult(a, b)
    a * b
  end

  mult(6, 2)
  mult(6, 2)
}

# Test for opt_div
assert_equal '3', %q{
  def div(a, b)
    a / b
  end

  div(6, 2)
  div(6, 2)
}

# BOP redefined methods work when JIT compiled
assert_equal 'false', %q{
  def less_than x
    x < 10
  end

  class Integer
    def < x
      false
    end
  end

  less_than 2
  less_than 2
  less_than 2
}

# BOP redefinition works on Integer#<
assert_equal 'false', %q{
  def less_than x
    x < 10
  end

  less_than 2
  less_than 2

  class Integer
    def < x
      false
    end
  end

  less_than 2
}

# BOP redefinition works on Integer#<=
assert_equal 'false', %q{
  def le(x, y) = x <= y

  le(2, 2)

  class Integer
    def <=(_) = false
  end

  le(2, 2)
}

# BOP redefinition works on Integer#>
assert_equal 'false', %q{
  def gt(x, y) = x > y

  gt(3, 2)

  class Integer
    def >(_) = false
  end

  gt(3, 2)
}

# BOP redefinition works on Integer#>=
assert_equal 'false', %q{
  def ge(x, y) = x >= y

  ge(2, 2)

  class Integer
    def >=(_) = false
  end

  ge(2, 2)
}

# Putobject, less-than operator, fixnums
assert_equal '2', %q{
    def check_index(index)
        if 0x40000000 < index
            raise "wat? #{index}"
        end
        index
    end
    check_index 2
    check_index 2
}

# foo leaves a temp on the stack before the call
assert_equal '6', %q{
    def bar
        return 5
    end

    def foo
        return 1 + bar
    end

    foo()
    retval = foo()
}

# Method with one arguments
# foo leaves a temp on the stack before the call
assert_equal '7', %q{
    def bar(a)
        return a + 1
    end

    def foo
        return 1 + bar(5)
    end

    foo()
    retval = foo()
}

# Method with two arguments
# foo leaves a temp on the stack before the call
assert_equal '0', %q{
    def bar(a, b)
        return a - b
    end

    def foo
        return 1 + bar(1, 2)
    end

    foo()
    retval = foo()
}

# Passing argument types to callees
assert_equal '8.5', %q{
    def foo(x, y)
        x + y
    end

    def bar
        foo(7, 1.5)
    end

    bar
    bar
}

# Recursive Ruby-to-Ruby calls
assert_equal '21', %q{
    def fib(n)
        if n < 2
            return n
        end

        return fib(n-1) + fib(n-2)
    end

    r = fib(8)
}

# Ruby-to-Ruby call and C call
assert_normal_exit %q{
  def bar
    puts('hi!')
  end

  def foo
    bar
  end

  foo()
  foo()
}

# Method aliasing
assert_equal '42', %q{
  class Foo
    def method_a
      42
    end

    alias method_b method_a

    def method_a
        :somethingelse
    end
  end

  @obj = Foo.new

  def test
    @obj.method_b
  end

  test
  test
}

# Method aliasing with method from parent class
assert_equal '777', %q{
  class A
    def method_a
      777
    end
  end

  class B < A
    alias method_b method_a
  end

  @obj = B.new

  def test
    @obj.method_b
  end

  test
  test
}

# The hash method is a C function and uses the self argument
assert_equal 'true', %q{
    def lehashself
        hash
    end

    a = lehashself
    b = lehashself
    a == b
}

# Method redefinition (code invalidation) test
assert_equal '1', %q{
    def ret1
        return 1
    end

    klass = Class.new do
        def alias_then_hash(klass, method_to_redefine)
            # Redefine the method to be ret1
            klass.alias_method(method_to_redefine, :ret1)
            hash
        end
    end

    instance = klass.new

    i = 0
    while i < 12
        if i < 11
            # Redefine the bar method
            instance.alias_then_hash(klass, :bar)
        else
            # Redefine the hash method to be ret1
            retval = instance.alias_then_hash(klass, :hash)
        end
        i += 1
    end

    retval
}

# Code invalidation and opt_getinlinecache
assert_normal_exit %q{
  class Foo; end

  # Uses the class constant Foo
  def use_constant(arg)
    [Foo.new, arg]
  end

  def propagate_type
    i = Array.new
    i.itself # make it remember that i is on-heap
    use_constant(i)
  end

  propagate_type
  propagate_type
  use_constant(Foo.new)
  class Jo; end # bump global constant state
  use_constant(3)
}

# Method redefinition (code invalidation) and GC
assert_equal '7', %q{
    def bar()
        return 5
    end

    def foo()
        bar()
    end

    foo()
    foo()

    def bar()
        return 7
    end

    4.times { GC.start }

    foo()
    foo()
}

# Method redefinition with two block versions
assert_equal '7', %q{
    def bar()
        return 5
    end

    def foo(n)
        return ((n < 5)? 5:false), bar()
    end

    foo(4)
    foo(4)
    foo(10)
    foo(10)

    def bar()
        return 7
    end

    4.times { GC.start }

    foo(4)
    foo(4)[1]
}

# Method redefinition while the method is on the stack
assert_equal '[777, 1]', %q{
    def foo
        redef()
        777
    end

    def redef
        # Redefine the global foo
        eval("def foo; 1; end", TOPLEVEL_BINDING)

        # Collect dead code
        GC.stress = true
        GC.start

        # But we will return to the original foo,
        # which remains alive because it's on the stack
    end

    # Must produce [777, 1]
    [foo, foo]
}

# Test for GC safety. Don't invalidate dead iseqs.
assert_normal_exit %q{
  Class.new do
    def foo
      itself
    end

    new.foo
    new.foo
    new.foo
    new.foo
  end

  4.times { GC.start }
  def itself
    self
  end
}

# test setinstancevariable on extended objects
assert_equal '1', %q{
  class Extended
    attr_reader :one

    def write_many
      @a = 1
      @b = 2
      @c = 3
      @d = 4
      @one = 1
    end
  end

  foo = Extended.new
  foo.write_many
  foo.write_many
  foo.write_many
}

# test setinstancevariable on embedded objects
assert_equal '1', %q{
  class Embedded
    attr_reader :one

    def write_one
      @one = 1
    end
  end

  foo = Embedded.new
  foo.write_one
  foo.write_one
  foo.write_one
}

# test setinstancevariable after extension
assert_equal '[10, 11, 12, 13, 1]', %q{
  class WillExtend
    attr_reader :one

    def make_extended
      @foo1 = 10
      @foo2 = 11
      @foo3 = 12
      @foo4 = 13
    end

    def write_one
      @one = 1
    end

    def read_all
      [@foo1, @foo2, @foo3, @foo4, @one]
    end
  end

  foo = WillExtend.new
  foo.write_one
  foo.write_one
  foo.make_extended
  foo.write_one
  foo.read_all
}

# test setinstancevariable on frozen object
assert_equal 'object was not modified', %q{
  class WillFreeze
    def write
      @ivar = 1
    end
  end

  wf = WillFreeze.new
  wf.write
  wf.write
  wf.freeze

  begin
    wf.write
  rescue FrozenError
    "object was not modified"
  end
}

# Test getinstancevariable and inline caches
assert_equal '6', %q{
  class Foo
    def initialize
      @x1 = 1
      @x2 = 1
      @x2 = 1
      @x3 = 1
      @x4 = 3
    end

    def bar
      x = 1
      @x4 + @x4
    end
  end

  f = Foo.new
  f.bar
  f.bar
}

# Test that getinstancevariable codegen checks for extended table size
assert_equal "nil\n", %q{
  class A
    def read
      @ins1000
    end
  end

  ins = A.new
  other = A.new
  10.times { other.instance_variable_set(:"@otr#{_1}", 'value') }
  1001.times { ins.instance_variable_set(:"@ins#{_1}", 'value') }

  ins.read
  ins.read
  ins.read

  p other.read
}

# Test that opt_aref checks the class of the receiver
assert_equal 'special', %q{
  def foo(array)
    array[30]
  end

  foo([])
  foo([])

  special = []
  def special.[](idx)
    'special'
  end

  foo(special)
}

# Test that object references in generated code get marked and moved
assert_equal "good", %q{
  skip :good unless GC.respond_to?(:compact)
  def bar
    "good"
  end

  def foo
    bar
  end

  foo
  foo

  begin
    GC.verify_compaction_references(expand_heap: true, toward: :empty)
  rescue NotImplementedError
    # in case compaction isn't supported
  end

  foo
}

# Test polymorphic getinstancevariable. T_OBJECT -> T_STRING
assert_equal 'ok', %q{
  @hello = @h1 = @h2 = @h3 = @h4 = 'ok'
  str = +""
  str.instance_variable_set(:@hello, 'ok')

  public def get
    @hello
  end

  get
  get
  str.get
  str.get
}

# Test polymorphic getinstancevariable, two different classes
assert_equal 'ok', %q{
  class Embedded
    def initialize
      @ivar = 0
    end

    def get
      @ivar
    end
  end

  class Extended < Embedded
    def initialize
      @v1 = @v2 = @v3 = @v4 = @ivar = 'ok'
    end
  end

  embed = Embedded.new
  extend = Extended.new

  embed.get
  embed.get
  extend.get
  extend.get
}

# Test megamorphic getinstancevariable
assert_equal 'ok', %q{
  parent = Class.new do
    def initialize
      @hello = @h1 = @h2 = @h3 = @h4 = 'ok'
    end

    def get
      @hello
    end
  end

  subclasses = 300.times.map { Class.new(parent) }
  subclasses.each { _1.new.get }
  parent.new.get
}

# Test polymorphic opt_aref. array -> hash
assert_equal '[42, :key]', %q{
  def index(obj, idx)
    obj[idx]
  end

  index([], 0) # get over compilation threshold

  [
    index([42], 0),
    index({0=>:key}, 0),
  ]
}

# Test polymorphic opt_aref. hash -> array -> custom class
assert_equal '[nil, nil, :custom]', %q{
  def index(obj, idx)
    obj[idx]
  end

  custom = Object.new
  def custom.[](_idx)
    :custom
  end

  index({}, 0) # get over compilation threshold

  [
    index({}, 0),
    index([], 0),
    index(custom, 0)
  ]
}

# Test polymorphic opt_aref. array -> custom class
assert_equal '[42, :custom]', %q{
  def index(obj, idx)
    obj[idx]
  end

  custom = Object.new
  def custom.[](_idx)
    :custom
  end

  index([], 0) # get over compilation threshold

  [
    index([42], 0),
    index(custom, 0)
  ]
}

# Test custom hash method with opt_aref
assert_equal '[nil, :ok]', %q{
  def index(obj, idx)
    obj[idx]
  end

  custom = Object.new
  def custom.hash
    42
  end

  h = {custom => :ok}

  [
    index(h, 0),
    index(h, custom)
  ]
}

# Test default value block for Hash with opt_aref
assert_equal '[42, :default]', %q{
  def index(obj, idx)
    obj[idx]
  end

  h = Hash.new { :default }
  h[0] = 42

  [
    index(h, 0),
    index(h, 1)
  ]
}

# Test default value block for Hash with opt_aref_with
assert_equal "false", <<~RUBY, frozen_string_literal: false
  def index_with_string(h)
    h["foo"]
  end

  h = Hash.new { |h, k| k.frozen? }

  index_with_string(h)
  index_with_string(h)
RUBY

# A regression test for making sure cfp->sp is proper when
# hitting stubs. See :stub-sp-flush:
assert_equal 'ok', %q{
  class D
    def foo
      Object.new
    end
  end

  GC.stress = true
  10.times do
    D.new.foo
    #    ^
    #  This hits a stub with sp_offset > 0
  end

  :ok
}

# Test polymorphic callsite, cfunc -> iseq
assert_equal '[Cfunc, Iseq]', %q{
  public def call_itself
    itself # the polymorphic callsite
  end

  class Cfunc; end

  class Iseq
    def itself
      self
    end
  end

  call_itself # cross threshold

  [Cfunc.call_itself, Iseq.call_itself]
}

# Test polymorphic callsite, iseq -> cfunc
assert_equal '[Iseq, Cfunc]', %q{
  public def call_itself
    itself # the polymorphic callsite
  end

  class Cfunc; end

  class Iseq
    def itself
      self
    end
  end

  call_itself # cross threshold

  [Iseq.call_itself, Cfunc.call_itself]
}

# attr_reader method
assert_equal '[100, 299]', %q{
  class A
    attr_reader :foo

    def initialize
      @foo = 100
    end

    # Make it extended
    def fill!
      @bar = @jojo = @as = @sdfsdf = @foo = 299
    end
  end

  def bar(ins)
    ins.foo
  end

  ins = A.new
  oth = A.new
  oth.fill!

  bar(ins)
  bar(oth)

  [bar(ins), bar(oth)]
}

# get ivar on object, then on hash
assert_equal '[42, 100]', %q{
  class Hash
    attr_accessor :foo
  end

  class A
    attr_reader :foo

    def initialize
      @foo = 42
    end
  end

  def use(val)
    val.foo
  end


  h = {}
  h.foo = 100
  obj = A.new

  use(obj)
  [use(obj), use(h)]
}

# get ivar on String
assert_equal '[nil, nil, 42, 42]', %q{
  # @foo to exercise the getinstancevariable instruction
  public def get_foo
    @foo
  end

  get_foo
  get_foo # compile it for the top level object

  class String
    attr_reader :foo
  end

  def run
    str = String.new

    getter = str.foo
    insn = str.get_foo

    str.instance_variable_set(:@foo, 42)

    [getter, insn, str.foo, str.get_foo]
  end

  run
  run
}

# splatting an empty array on a getter
assert_equal '42', %q{
  @foo = 42
  module Kernel
    attr_reader :foo
  end

  def run
    foo(*[])
  end

  run
  run
}

# splatting an empty array on a specialized method
assert_equal 'ok', %q{
  def run
    "ok".to_s(*[])
  end

  run
  run
}

# splatting an single element array on a specialized method
assert_equal '[1]', %q{
  def run
    [].<<(*[1])
  end

  run
  run
}

# specialized method with wrong args
assert_equal 'ok', %q{
  def run(x)
    "bad".to_s(123) if x
  rescue
    :ok
  end

  run(false)
  run(true)
}

# getinstancevariable on Symbol
assert_equal '[nil, nil]', %q{
  # @foo to exercise the getinstancevariable instruction
  public def get_foo
    @foo
  end

  dyn_sym = ("a" + "b").to_sym
  sym = :static

  # compile get_foo
  dyn_sym.get_foo
  dyn_sym.get_foo

  [dyn_sym.get_foo, sym.get_foo]
}

# attr_reader on Symbol
assert_equal '[nil, nil]', %q{
  class Symbol
    attr_reader :foo
  end

  public def get_foo
    foo
  end

  dyn_sym = ("a" + "b").to_sym
  sym = :static

  # compile get_foo
  dyn_sym.get_foo
  dyn_sym.get_foo

  [dyn_sym.get_foo, sym.get_foo]
}

# passing too few arguments to method with optional parameters
assert_equal 'raised', %q{
  def opt(a, b = 0)
  end

  def use
    opt
  end

  use rescue nil
  begin
    use
    :ng
  rescue ArgumentError
    :raised
  end
}

# passing too many arguments to method with optional parameters
assert_equal 'raised', %q{
  def opt(a, b = 0)
  end

  def use
    opt(1, 2, 3, 4)
  end

  use rescue nil
  begin
    use
    :ng
  rescue ArgumentError
    :raised
  end
}

# test calling Ruby method with a block
assert_equal '[1, 2, 42]', %q{
  def thing(a, b)
    [a, b, yield]
  end

  def use
    thing(1,2) { 42 }
  end

  use
  use
}

# test calling C method with a block
assert_equal '[42, 42]', %q{
  def use(array, initial)
    array.reduce(initial) { |a, b| a + b }
  end

  use([], 0)
  [use([2, 2], 38), use([14, 14, 14], 0)]
}

# test calling block param
assert_equal '[1, 2, 42]', %q{
  def foo(&block)
    block.call
  end

  [foo {1}, foo {2}, foo {42}]
}

# test calling without block param
assert_equal '[1, false, 2, false]', %q{
  def bar
    block_given? && yield
  end

  def foo(&block)
    bar(&block)
  end

  [foo { 1 }, foo, foo { 2 }, foo]
}

# test calling block param failing
assert_equal '42', %q{
  def foo(&block)
    block.call
  end

  foo {} # warmup

  begin
    foo
  rescue NoMethodError => e
    42 if nil == e.receiver
  end
}

# test calling method taking block param
assert_equal '[Proc, 1, 2, 3, Proc]', %q{
  def three(a, b, c, &block)
    [a, b, c, block.class]
  end

  def zero(&block)
    block.class
  end

  def use_three
    three(1, 2, 3) {}
  end

  def use_zero
    zero {}
  end

  use_three
  use_zero

  [use_zero] + use_three
}

# test building empty array
assert_equal '[]', %q{
  def build_arr
    []
  end

  build_arr
  build_arr
}

# test building array of one element
assert_equal '[5]', %q{
  def build_arr(val)
    [val]
  end

  build_arr(5)
  build_arr(5)
}

# test building array of several element
assert_equal '[5, 5, 5, 5, 5]', %q{
  def build_arr(val)
    [val, val, val, val, val]
  end

  build_arr(5)
  build_arr(5)
}

# test building empty hash
assert_equal '{}', %q{
  def build_hash
    {}
  end

  build_hash
  build_hash
}

# test building hash with values
assert_equal '{foo: :bar}', %q{
  def build_hash(val)
    { foo: val }
  end

  build_hash(:bar)
  build_hash(:bar)
}

# test string interpolation with known types
assert_equal 'foobar', %q{
  def make_str
    foo = -"foo"
    bar = -"bar"
    "#{foo}#{bar}"
  end

  make_str
  make_str
}

# test string interpolation with unknown types
assert_equal 'foobar', %q{
  def make_str(foo, bar)
    "#{foo}#{bar}"
  end

  make_str("foo", "bar")
  make_str("foo", "bar")
}

# test string interpolation with known non-strings
assert_equal 'foo123', %q{
  def make_str
    foo = -"foo"
    bar = 123
    "#{foo}#{bar}"
  end

  make_str
  make_str
}

# test string interpolation with unknown non-strings
assert_equal 'foo123', %q{
  def make_str(foo, bar)
    "#{foo}#{bar}"
  end

  make_str("foo", 123)
  make_str("foo", 123)
}

# test that invalidation of String#to_s doesn't crash
assert_equal 'meh', %q{
  def inval_method
    "".to_s
  end

  inval_method

  class String
    def to_s
      "meh"
    end
  end

  inval_method
}

# test that overriding to_s on a String subclass works consistently
assert_equal 'meh', %q{
  class MyString < String
    def to_s
      "meh"
    end
  end

  def test_to_s(obj)
    obj.to_s
  end

  OBJ = MyString.new

  # Should return '' both times
  test_to_s("")
  test_to_s("")

  # Can return '' if YJIT optimises String#to_s too aggressively
  test_to_s(OBJ)
  test_to_s(OBJ)
}

# test string interpolation with overridden to_s
assert_equal 'foo', %q{
  class String
    def to_s
      "bad"
    end
  end

  def make_str(foo)
    "#{foo}"
  end

  make_str("foo")
  make_str("foo")
}

# Test that String unary plus returns the same object ID for an unfrozen string.
assert_equal 'true', <<~RUBY, frozen_string_literal: false
  def jittable_method
    str = "bar"

    old_obj_id = str.object_id
    uplus_str = +str

    uplus_str.object_id == old_obj_id
  end
  jittable_method
RUBY

# Test that String unary plus returns a different unfrozen string when given a frozen string
assert_equal 'false', %q{
  # Logic needs to be inside an ISEQ, such as a method, for YJIT to compile it
  def jittable_method
    frozen_str = "foo".freeze

    old_obj_id = frozen_str.object_id
    uplus_str = +frozen_str

    uplus_str.object_id == old_obj_id || uplus_str.frozen?
  end

  jittable_method
}

# String-subclass objects should behave as expected inside string-interpolation via concatstrings
assert_equal 'monkeys / monkeys, yo!', %q{
  class MyString < String
    # This is a terrible idea in production code, but we'd like YJIT to match CRuby
    def to_s
      super + ", yo!"
    end
  end

  def jittable_method
    m = MyString.new('monkeys')
    "#{m} / #{m.to_s}"
  end

  jittable_method
}

# String-subclass objects should behave as expected for string equality
assert_equal 'false', %q{
  class MyString < String
    # This is a terrible idea in production code, but we'd like YJIT to match CRuby
    def ==(b)
      "#{self}_" == b
    end
  end

  def jittable_method
    ma = MyString.new("a")

    # Check equality with string-subclass receiver
    ma == "a" || ma != "a_" ||
      # Check equality with string receiver
      "a_" == ma || "a" != ma ||
      # Check equality between string subclasses
      ma != MyString.new("a_") ||
      # Make sure "string always equals itself" check isn't used with overridden equality
      ma == ma
  end
  jittable_method
}

# Test to_s duplicates a string subclass object but not a string
assert_equal 'false', %q{
  class MyString < String; end

  def jittable_method
    a = "a"
    ma = MyString.new("a")

    a.object_id != a.to_s.object_id ||
      ma.object_id == ma.to_s.object_id
  end
  jittable_method
}

# Test freeze on string subclass
assert_equal 'true', %q{
  class MyString < String; end

  def jittable_method
    fma = MyString.new("a").freeze

    # Freezing a string subclass should not duplicate it
    fma.object_id == fma.freeze.object_id
  end
  jittable_method
}

# Test unary minus on string subclass
assert_equal 'true', %q{
  class MyString < String; end

  def jittable_method
    ma = MyString.new("a")
    fma = MyString.new("a").freeze

    # Unary minus on frozen string subclass should not duplicate it
    fma.object_id == (-fma).object_id &&
      # Unary minus on unfrozen string subclass should duplicate it
      ma.object_id != (-ma).object_id
  end
  jittable_method
}

# Test unary plus on string subclass
assert_equal 'true', %q{
  class MyString < String; end

  def jittable_method
    fma = MyString.new("a").freeze

    # Unary plus on frozen string subclass should not duplicate it
    fma.object_id != (+fma).object_id
  end
  jittable_method
}

# test getbyte on string class
assert_equal '[97, :nil, 97, :nil, :raised]', %q{
  def getbyte(s, i)
   byte = begin
    s.getbyte(i)
   rescue TypeError
    :raised
   end

   byte || :nil
  end

  getbyte("a", 0)
  getbyte("a", 0)

  [getbyte("a", 0), getbyte("a", 1), getbyte("a", -1), getbyte("a", -2), getbyte("a", "a")]
}

# Basic test for String#setbyte
assert_equal 'AoZ', %q{
  s = +"foo"
  s.setbyte(0, 65)
  s.setbyte(-1, 90)
  s
}

# String#setbyte IndexError
assert_equal 'String#setbyte', %q{
  def ccall = "".setbyte(1, 0)
  begin
    ccall
  rescue => e
    e.backtrace.first.split("'").last
  end
}

# String#setbyte TypeError
assert_equal 'String#setbyte', %q{
  def ccall = "".setbyte(nil, 0)
  begin
    ccall
  rescue => e
    e.backtrace.first.split("'").last
  end
}

# String#setbyte FrozenError
assert_equal 'String#setbyte', %q{
  def ccall = "a".freeze.setbyte(0, 0)
  begin
    ccall
  rescue => e
    e.backtrace.first.split("'").last
  end
}

# non-leaf String#setbyte
assert_equal 'String#setbyte', %q{
  def to_int
    @caller = caller
    0
  end

  def ccall = "a".dup.setbyte(self, 98)
  ccall

  @caller.first.split("'").last
}

# non-leaf String#byteslice
assert_equal 'TypeError', %q{
  def ccall = "".byteslice(nil, nil)
  begin
    ccall
  rescue => e
    e.class
  end
}

# Test << operator on string subclass
assert_equal 'abab', %q{
  class MyString < String; end

  def jittable_method
    a = -"a"
    mb = MyString.new("b")

    buf = String.new
    mbuf = MyString.new

    buf << a << mb
    mbuf << a << mb

    buf + mbuf
  end
  jittable_method
}

# test invokebuiltin as used in struct assignment
assert_equal '123', %q{
  def foo(obj)
    obj.foo = 123
  end

  struct = Struct.new(:foo)
  obj = struct.new
  foo(obj)
  foo(obj)
}

# test invokebuiltin_delegate as used inside Dir.open
assert_equal '.', %q{
  def foo(path)
    Dir.open(path).path
  end

  foo(".")
  foo(".")
}

# test invokebuiltin_delegate_leave in method called from jit
assert_normal_exit %q{
  def foo(obj)
    obj.clone
  end

  foo(Object.new)
  foo(Object.new)
}

# test invokebuiltin_delegate_leave in method called from cfunc
assert_normal_exit %q{
  def foo(obj)
    [obj].map(&:clone)
  end

  foo(Object.new)
  foo(Object.new)
}

# defining TrueClass#!
assert_equal '[false, false, :ok]', %q{
  def foo(obj)
    !obj
  end

  x = foo(true)
  y = foo(true)

  class TrueClass
    def !
      :ok
    end
  end

  z = foo(true)

  [x, y, z]
}

# defining FalseClass#!
assert_equal '[true, true, :ok]', %q{
  def foo(obj)
    !obj
  end

  x = foo(false)
  y = foo(false)

  class FalseClass
    def !
      :ok
    end
  end

  z = foo(false)

  [x, y, z]
}

# defining NilClass#!
assert_equal '[true, true, :ok]', %q{
  def foo(obj)
    !obj
  end

  x = foo(nil)
  y = foo(nil)

  class NilClass
    def !
      :ok
    end
  end

  z = foo(nil)

  [x, y, z]
}

# polymorphic opt_not
assert_equal '[true, true, false, false, false, false, false]', %q{
  def foo(obj)
    !obj
  end

  foo(0)
  [foo(nil), foo(false), foo(true), foo([]), foo(0), foo(4.2), foo(:sym)]
}

# getlocal with 2 levels
assert_equal '7', %q{
  def foo(foo, bar)
    while foo > 0
      while bar > 0
        return foo + bar
      end
    end
  end

  foo(5,2)
  foo(5,2)
}

# regression test for argument registers with invalidation
assert_equal '[0, 1, 2]', %q{
  def test(n)
    ret = n
    binding
    ret
  end

  [0, 1, 2].map do |n|
    test(n)
  end
}

# regression test for argument registers
assert_equal 'true', %q{
  class Foo
    def ==(other)
      other == nil
    end
  end

  def test
    [Foo.new].include?(Foo.new)
  end

  test
}

# test pattern matching
assert_equal '[:ok, :ok]', %q{
  class C
    def destructure_keys
      {}
    end
  end

  pattern_match = ->(i) do
    case i
    in a: 0
      :ng
    else
      :ok
    end
  end

  [{}, C.new].map(&pattern_match)
}

# Call to object with singleton
assert_equal '123', %q{
  obj = Object.new
  def obj.foo
    123
  end

  def foo(obj)
    obj.foo()
  end

  foo(obj)
  foo(obj)
}

# Call method on an object that has a non-material
# singleton class.
# TODO: assert that it takes no side exits? This
# test case revealed that we were taking exits unnecessarily.
assert_normal_exit %q{
  def foo(obj)
    obj.itself
  end

  o = Object.new.singleton_class
  foo(o)
  foo(o)
}

# Call to singleton class
assert_equal '123', %q{
  class Foo
    def self.foo
      123
    end
  end

  def foo(obj)
    obj.foo()
  end

  foo(Foo)
  foo(Foo)
}

# Test EP == BP invalidation with moving ISEQs
assert_equal 'ok', %q{
  skip :ok unless GC.respond_to?(:compact)
  def entry
    ok = proc { :ok } # set #entry as an EP-escaping ISEQ
    [nil].reverse_each do # avoid exiting the JIT frame on the constant
      GC.compact # move #entry ISEQ
    end
    ok # should be read off of escaped EP
  end

  entry.call
}

# invokesuper edge case
assert_equal '[:A, [:A, :B]]', %q{
  class B
    def foo = :B
  end

  class A < B
    def foo = [:A, super()]
  end

  A.new.foo
  A.new.foo # compile A#foo

  class C < A
    define_method(:bar, A.instance_method(:foo))
  end

  C.new.bar
}

# Same invokesuper bytecode, multiple destinations
assert_equal '[:Forward, :SecondTerminus]', %q{
  module Terminus
    def foo = :Terminus
  end

  module SecondTerminus
    def foo = :SecondTerminus
  end


  module Forward
    def foo = [:Forward, super]
  end

  class B
    include SecondTerminus
  end

  class A < B
    include Terminus
    include Forward
  end

  A.new.foo
  A.new.foo # compile

  class B
    include Forward
    alias bar foo
  end

  # A.ancestors.take(5) == [A, Forward, Terminus, B, Forward, SecondTerminus]

  A.new.bar
}

# invokesuper calling into itself
assert_equal '[:B, [:B, :m]]', %q{
  module M
    def foo = :m
  end

  class B
    include M
    def foo = [:B, super]
  end

  ins = B.new
  ins.singleton_class # materialize the singleton class
  ins.foo
  ins.foo # compile

  ins.singleton_class.define_method(:bar, B.instance_method(:foo))
  ins.bar
}

# invokesuper changed ancestor
assert_equal '[:A, [:M, :B]]', %q{
  class B
    def foo
      :B
    end
  end

  class A < B
    def foo
      [:A, super]
    end
  end

  module M
    def foo
      [:M, super]
    end
  end

  ins = A.new
  ins.foo
  ins.foo
  A.include(M)
  ins.foo
}

# invokesuper changed ancestor via prepend
assert_equal '[:A, [:M, :B]]', %q{
  class B
    def foo
      :B
    end
  end

  class A < B
    def foo
      [:A, super]
    end
  end

  module M
    def foo
      [:M, super]
    end
  end

  ins = A.new
  ins.foo
  ins.foo
  B.prepend(M)
  ins.foo
}

# invokesuper replaced method
assert_equal '[:A, :Btwo]', %q{
  class B
    def foo
      :B
    end
  end

  class A < B
    def foo
      [:A, super]
    end
  end

  ins = A.new
  ins.foo
  ins.foo
  class B
    def foo
      :Btwo
    end
  end
  ins.foo
}

# invokesuper with a block
assert_equal 'true', %q{
  class A
    def foo = block_given?
  end

  class B < A
    def foo = super()
  end

  B.new.foo { }
  B.new.foo { }
}

# invokesuper in a block
assert_equal '[0, 2]', %q{
  class A
    def foo(x) = x * 2
  end

  class B < A
    def foo
      2.times.map do |x|
        super(x)
      end
    end
  end

  B.new.foo
  B.new.foo
}

# invokesuper zsuper in a bmethod
assert_equal 'ok', %q{
  class Foo
    define_method(:itself) { super }
  end
  begin
    Foo.new.itself
  rescue RuntimeError
    :ok
  end
}

# Call to fixnum
assert_equal '[true, false]', %q{
  def is_odd(obj)
    obj.odd?
  end

  is_odd(1)
  is_odd(1)

  [is_odd(123), is_odd(456)]
}

# Call to bignum
assert_equal '[true, false]', %q{
  def is_odd(obj)
    obj.odd?
  end

  bignum = 99999999999999999999
  is_odd(bignum)
  is_odd(bignum)

  [is_odd(bignum), is_odd(bignum+1)]
}

# Call to fixnum and bignum
assert_equal '[true, false, true, false]', %q{
  def is_odd(obj)
    obj.odd?
  end

  bignum = 99999999999999999999
  is_odd(bignum)
  is_odd(bignum)
  is_odd(123)
  is_odd(123)

  [is_odd(123), is_odd(456), is_odd(bignum), is_odd(bignum+1)]
}

# Flonum and Flonum
assert_equal '[2.0, 0.0, 1.0, 4.0]', %q{
  [1.0 + 1.0, 1.0 - 1.0, 1.0 * 1.0, 8.0 / 2.0]
}

# Flonum and Fixnum
assert_equal '[2.0, 0.0, 1.0, 4.0]', %q{
  [1.0 + 1, 1.0 - 1, 1.0 * 1, 8.0 / 2]
}

# Call to static and dynamic symbol
assert_equal 'bar', %q{
  def to_string(obj)
    obj.to_s
  end

  to_string(:foo)
  to_string(:foo)
  to_string((-"bar").to_sym)
  to_string((-"bar").to_sym)
}

# Call to flonum and heap float
assert_equal '[nil, nil, nil, 1]', %q{
  def is_inf(obj)
    obj.infinite?
  end

  is_inf(0.0)
  is_inf(0.0)
  is_inf(1e256)
  is_inf(1e256)

  [
    is_inf(0.0),
    is_inf(1.0),
    is_inf(1e256),
    is_inf(1.0/0.0)
  ]
}

assert_equal '[1, 2, 3, 4, 5]', %q{
  def splatarray
    [*(1..5)]
  end

  splatarray
  splatarray
}

# splatkw
assert_equal '[1, 2]', %q{
  def foo(a:) = [a, yield]

  def entry(&block)
    a = { a: 1 }
    foo(**a, &block)
  end

  entry { 2 }
}
assert_equal '[1, 2]', %q{
  def foo(a:) = [a, yield]

  def entry(obj, &block)
    foo(**obj, &block)
  end

  entry({ a: 3 }) { 2 }
  obj = Object.new
  def obj.to_hash = { a: 1 }
  entry(obj) { 2 }
}

assert_equal '[1, 1, 2, 1, 2, 3]', %q{
  def expandarray
    arr = [1, 2, 3]

    a, = arr
    b, c, = arr
    d, e, f = arr

    [a, b, c, d, e, f]
  end

  expandarray
  expandarray
}

assert_equal '[1, 1]', %q{
  def expandarray_useless_splat
    arr = (1..10).to_a

    a, * = arr
    b, (*) = arr

    [a, b]
  end

  expandarray_useless_splat
  expandarray_useless_splat
}

assert_equal '[:not_heap, nil, nil]', %q{
  def expandarray_not_heap
    a, b, c = :not_heap
    [a, b, c]
  end

  expandarray_not_heap
  expandarray_not_heap
}

assert_equal '[:not_array, nil, nil]', %q{
  def expandarray_not_array(obj)
    a, b, c = obj
    [a, b, c]
  end

  obj = Object.new
  def obj.to_ary
    [:not_array]
  end

  expandarray_not_array(obj)
  expandarray_not_array(obj)
}

assert_equal '[1, 2]', %q{
  class NilClass
    private
    def to_ary
      [1, 2]
    end
  end

  def expandarray_redefined_nilclass
    a, b = nil
    [a, b]
  end

  expandarray_redefined_nilclass
  expandarray_redefined_nilclass
}

assert_equal '[1, 2, nil]', %q{
  def expandarray_rhs_too_small
    a, b, c = [1, 2]
    [a, b, c]
  end

  expandarray_rhs_too_small
  expandarray_rhs_too_small
}

assert_equal '[nil, 2, nil]', %q{
  def foo(arr)
    a, b, c = arr
  end

  a, b, c1 = foo([0, 1])
  a, b, c2 = foo([0, 1, 2])
  a, b, c3 = foo([0, 1])
  [c1, c2, c3]
}

assert_equal '[1, [2]]', %q{
  def expandarray_splat
    a, *b = [1, 2]
    [a, b]
  end

  expandarray_splat
  expandarray_splat
}

assert_equal '2', %q{
  def expandarray_postarg
    *, a = [1, 2]
    a
  end

  expandarray_postarg
  expandarray_postarg
}

assert_equal '10', %q{
  obj = Object.new
  val = nil
  obj.define_singleton_method(:to_ary) { val = 10; [] }

  def expandarray_always_call_to_ary(object)
    * = object
  end

  expandarray_always_call_to_ary(obj)
  expandarray_always_call_to_ary(obj)

  val
}

# regression test of local type change
assert_equal '1.1', %q{
def bar(baz, quux)
  if baz.integer?
    baz, quux = quux, nil
  end
  baz.to_s
end

bar(123, 1.1)
bar(123, 1.1)
}

# test enabling a line TracePoint in a C method call
assert_equal '[[:line, true]]', %q{
  events = []
  events.instance_variable_set(
    :@tp,
    TracePoint.new(:line) { |tp| events << [tp.event, tp.lineno] if tp.path == __FILE__ }
  )
  def events.to_str
    @tp.enable; ''
  end

  # Stay in generated code while enabling tracing
  def events.compiled(obj)
    String(obj)
    @tp.disable; __LINE__
  end

  line = events.compiled(events)
  events[0][-1] = (events[0][-1] == line)

  events
}

# test enabling a c_return TracePoint in a C method call
assert_equal '[[:c_return, :String, :string_alias, "events_to_str"]]', %q{
  events = []
  events.instance_variable_set(:@tp, TracePoint.new(:c_return) { |tp| events << [tp.event, tp.method_id, tp.callee_id, tp.return_value] })
  def events.to_str
    @tp.enable; 'events_to_str'
  end

  # Stay in generated code while enabling tracing
  alias string_alias String
  def events.compiled(obj)
    string_alias(obj)
    @tp.disable
  end

  events.compiled(events)

  events
}

# test enabling a TracePoint that targets a particular line in a C method call
assert_equal '[true]', %q{
  events = []
  events.instance_variable_set(:@tp, TracePoint.new(:line) { |tp| events << tp.lineno })
  def events.to_str
    @tp.enable(target: method(:compiled))
    ''
  end

  # Stay in generated code while enabling tracing
  def events.compiled(obj)
    String(obj)
    __LINE__
  end

  line = events.compiled(events)
  events[0] = (events[0] == line)

  events
}

# test enabling tracing in the middle of splatarray
assert_equal '[true]', %q{
  events = []
  obj = Object.new
  obj.instance_variable_set(:@tp, TracePoint.new(:line) { |tp| events << tp.lineno })
  def obj.to_a
    @tp.enable(target: method(:compiled))
    []
  end

  # Enable tracing in the middle of the splatarray instruction
  def obj.compiled(obj)
    * = *obj
    __LINE__
  end

  obj.compiled([])
  line = obj.compiled(obj)
  events[0] = (events[0] == line)

  events
}

# test enabling tracing in the middle of opt_aref. Different since the codegen
# for it ends in a jump.
assert_equal '[true]', %q{
  def lookup(hash, tp)
    hash[42]
    tp.disable; __LINE__
  end

  lines = []
  tp = TracePoint.new(:line) { lines << _1.lineno if _1.path == __FILE__ }

  lookup(:foo, tp)
  lookup({}, tp)

  enable_tracing_on_missing = Hash.new { tp.enable }

  expected_line = lookup(enable_tracing_on_missing, tp)

  lines[0] = true if lines[0] == expected_line

  lines
}

# test enabling c_call tracing before compiling
assert_equal '[[:c_call, :itself]]', %q{
  def shouldnt_compile
    itself
  end

  events = []
  tp = TracePoint.new(:c_call) { |tp| events << [tp.event, tp.method_id] }

  # assume first call compiles
  tp.enable { shouldnt_compile }

  events
}

# test enabling c_return tracing before compiling
assert_equal '[[:c_return, :itself, main]]', %q{
  def shouldnt_compile
    itself
  end

  events = []
  tp = TracePoint.new(:c_return) { |tp| events << [tp.event, tp.method_id, tp.return_value] }

  # assume first call compiles
  tp.enable { shouldnt_compile }

  events
}

# test c_call invalidation
assert_equal '[[:c_call, :itself]]', %q{
  # enable the event once to make sure invalidation
  # happens the second time we enable it
  TracePoint.new(:c_call) {}.enable{}

  def compiled
    itself
  end

  # assume first call compiles
  compiled

  events = []
  tp = TracePoint.new(:c_call) { |tp| events << [tp.event, tp.method_id] }
  tp.enable { compiled }

  events
}

# test enabling tracing for a suspended fiber
assert_equal '[[:return, 42]]', %q{
  def traced_method
    Fiber.yield
    42
  end

  events = []
  tp = TracePoint.new(:return) { events << [_1.event, _1.return_value] }
  # assume first call compiles
  fiber = Fiber.new { traced_method }
  fiber.resume
  tp.enable(target: method(:traced_method))
  fiber.resume

  events
}

# test compiling on non-tracing ractor then running on a tracing one
assert_equal '[:itself]', %q{
  def traced_method
    itself
  end

  tracing_ractor = Ractor.new do
    # 1: start tracing
    events = []
    tp = TracePoint.new(:c_call) { events << _1.method_id }
    tp.enable
    Ractor.yield(nil)

    # 3: run compiled method on tracing ractor
    Ractor.yield(nil)
    traced_method

    events
  ensure
    tp&.disable
  end

  tracing_ractor.take

  # 2: compile on non tracing ractor
  traced_method

  tracing_ractor.take
  tracing_ractor.take
}

# Try to hit a lazy branch stub while another ractor enables tracing
assert_equal '42', %q{
  def compiled(arg)
    if arg
      arg + 1
    else
      itself
      itself
    end
  end

  ractor = Ractor.new do
    compiled(false)
    Ractor.yield(nil)
    compiled(41)
  end

  tp = TracePoint.new(:line) { itself }
  ractor.take
  tp.enable

  ractor.take
}

# Test equality with changing types
assert_equal '[true, false, false, false]', %q{
  def eq(a, b)
    a == b
  end

  [
    eq("foo", "foo"),
    eq("foo", "bar"),
    eq(:foo, "bar"),
    eq("foo", :bar)
  ]
}

# Redefined String eq
assert_equal 'true', %q{
  class String
    def ==(other)
      true
    end
  end

  def eq(a, b)
    a == b
  end

  eq("foo", "bar")
  eq("foo", "bar")
}

# Redefined Integer eq
assert_equal 'true', %q{
  class Integer
    def ==(other)
      true
    end
  end

  def eq(a, b)
    a == b
  end

  eq(1, 2)
  eq(1, 2)
}

# aset on array with invalid key
assert_normal_exit %q{
  def foo(arr)
    arr[:foo] = 123
  end

  foo([1]) rescue nil
  foo([1]) rescue nil
}

# test ractor exception on when setting ivar
assert_equal '42',  %q{
  class A
    def self.foo
      _foo = 1
      _bar = 2
      begin
        @bar = _foo + _bar
      rescue Ractor::IsolationError
        42
      end
    end
  end

  A.foo
  A.foo

  Ractor.new { A.foo }.take
}

assert_equal '["plain", "special", "sub", "plain"]', %q{
  def foo(arg)
    arg.to_s
  end

  class Sub < String
  end

  special = String.new("special")
  special.singleton_class

  [
    foo("plain"),
    foo(special),
    foo(Sub.new("sub")),
    foo("plain")
  ]
}

assert_equal '["sub", "sub"]', %q{
  def foo(arg)
    arg.to_s
  end

  class Sub < String
    def to_s
      super
    end
  end

  sub = Sub.new("sub")

  [foo(sub), foo(sub)]
}

assert_equal '[1]', %q{
  def kwargs(value:)
    value
  end

  5.times.map { kwargs(value: 1) }.uniq
}

assert_equal '[:ok]', %q{
  def kwargs(value:)
    value
  end

  5.times.map { kwargs() rescue :ok }.uniq
}

assert_equal '[:ok]', %q{
  def kwargs(a:, b: nil)
    value
  end

  5.times.map { kwargs(b: 123) rescue :ok }.uniq
}

assert_equal '[[1, 2]]', %q{
  def kwargs(left:, right:)
    [left, right]
  end

  5.times.flat_map do
    [
      kwargs(left: 1, right: 2),
      kwargs(right: 2, left: 1)
    ]
  end.uniq
}

assert_equal '[[1, 2]]', %q{
  def kwargs(lead, kwarg:)
    [lead, kwarg]
  end

  5.times.map { kwargs(1, kwarg: 2) }.uniq
}

# optional and keyword args
assert_equal '[[1, 2, 3]]', %q{
  def opt_and_kwargs(a, b=2, c: nil)
    [a,b,c]
  end

  5.times.map { opt_and_kwargs(1, c: 3) }.uniq
}

assert_equal '[[1, 2, 3]]', %q{
  def opt_and_kwargs(a, b=nil, c: nil)
    [a,b,c]
  end

  5.times.map { opt_and_kwargs(1, 2, c: 3) }.uniq
}

# Bug #18453
assert_equal '[[1, nil, 2]]', %q{
  def opt_and_kwargs(a = {}, b: nil, c: nil)
    [a, b, c]
  end

  5.times.map { opt_and_kwargs(1, c: 2) }.uniq
}

assert_equal '[[{}, nil, 1]]', %q{
  def opt_and_kwargs(a = {}, b: nil, c: nil)
    [a, b, c]
  end

  5.times.map { opt_and_kwargs(c: 1) }.uniq
}

# leading and keyword arguments are swapped into the right order
assert_equal '[[1, 2, 3, 4, 5, 6]]', %q{
  def kwargs(five, six, a:, b:, c:, d:)
    [a, b, c, d, five, six]
  end

  5.times.flat_map do
    [
      kwargs(5, 6, a: 1, b: 2, c: 3, d: 4),
      kwargs(5, 6, a: 1, b: 2, d: 4, c: 3),
      kwargs(5, 6, a: 1, c: 3, b: 2, d: 4),
      kwargs(5, 6, a: 1, c: 3, d: 4, b: 2),
      kwargs(5, 6, a: 1, d: 4, b: 2, c: 3),
      kwargs(5, 6, a: 1, d: 4, c: 3, b: 2),
      kwargs(5, 6, b: 2, a: 1, c: 3, d: 4),
      kwargs(5, 6, b: 2, a: 1, d: 4, c: 3),
      kwargs(5, 6, b: 2, c: 3, a: 1, d: 4),
      kwargs(5, 6, b: 2, c: 3, d: 4, a: 1),
      kwargs(5, 6, b: 2, d: 4, a: 1, c: 3),
      kwargs(5, 6, b: 2, d: 4, c: 3, a: 1),
      kwargs(5, 6, c: 3, a: 1, b: 2, d: 4),
      kwargs(5, 6, c: 3, a: 1, d: 4, b: 2),
      kwargs(5, 6, c: 3, b: 2, a: 1, d: 4),
      kwargs(5, 6, c: 3, b: 2, d: 4, a: 1),
      kwargs(5, 6, c: 3, d: 4, a: 1, b: 2),
      kwargs(5, 6, c: 3, d: 4, b: 2, a: 1),
      kwargs(5, 6, d: 4, a: 1, b: 2, c: 3),
      kwargs(5, 6, d: 4, a: 1, c: 3, b: 2),
      kwargs(5, 6, d: 4, b: 2, a: 1, c: 3),
      kwargs(5, 6, d: 4, b: 2, c: 3, a: 1),
      kwargs(5, 6, d: 4, c: 3, a: 1, b: 2),
      kwargs(5, 6, d: 4, c: 3, b: 2, a: 1)
    ]
  end.uniq
}

# implicit hashes get skipped and don't break compilation
assert_equal '[[:key]]', %q{
  def implicit(hash)
    hash.keys
  end

  5.times.map { implicit(key: :value) }.uniq
}

# default values on keywords don't mess up argument order
assert_equal '[2]', %q{
  def default_value
    1
  end

  def default_expression(value: default_value)
    value
  end

  5.times.map { default_expression(value: 2) }.uniq
}

# constant default values on keywords
assert_equal '[3]', %q{
  def default_expression(value: 3)
    value
  end

  5.times.map { default_expression }.uniq
}

# non-constant default values on keywords
assert_equal '[3]', %q{
  def default_value
    3
  end

  def default_expression(value: default_value)
    value
  end

  5.times.map { default_expression }.uniq
}

# reordered optional kwargs
assert_equal '[[100, 1]]', %q{
  def foo(capacity: 100, max: nil)
    [capacity, max]
  end

  5.times.map { foo(max: 1) }.uniq
}

# invalid lead param
assert_equal 'ok', %q{
  def bar(baz: 2)
    baz
  end

  def foo
    bar(1, baz: 123)
  end

  begin
    foo
    foo
  rescue ArgumentError => e
    print "ok"
  end
}

# reordered required kwargs
assert_equal '[[1, 2, 3, 4]]', %q{
  def foo(default1: 1, required1:, default2: 3, required2:)
    [default1, required1, default2, required2]
  end

  5.times.map { foo(required1: 2, required2: 4) }.uniq
}

# reordered default expression kwargs
assert_equal '[[:one, :two, 3]]', %q{
  def foo(arg1: (1+0), arg2: (2+0), arg3: (3+0))
    [arg1, arg2, arg3]
  end

  5.times.map { foo(arg2: :two, arg1: :one) }.uniq
}

# complex kwargs
assert_equal '[[1, 2, 3, 4]]', %q{
  def foo(required:, specified: 999, simple_default: 3, complex_default: "4".to_i)
    [required, specified, simple_default, complex_default]
  end

  5.times.map { foo(specified: 2, required: 1) }.uniq
}

# cfunc kwargs
assert_equal '{foo: 123}', %q{
  def foo(bar)
    bar.store(:value, foo: 123)
    bar[:value]
  end

  foo({})
  foo({})
}

# cfunc kwargs
assert_equal '{foo: 123}', %q{
  def foo(bar)
    bar.replace(foo: 123)
  end

  foo({})
  foo({})
}

# cfunc kwargs
assert_equal '{foo: 123, bar: 456}', %q{
  def foo(bar)
    bar.replace(foo: 123, bar: 456)
  end

  foo({})
  foo({})
}

# variadic cfunc kwargs
assert_equal '{foo: 123}', %q{
  def foo(bar)
    bar.merge(foo: 123)
  end

  foo({})
  foo({})
}

# optimized cfunc kwargs
assert_equal 'false', %q{
  def foo
    :foo.eql?(foo: :foo)
  end

  foo
  foo
}

# attr_reader on frozen object
assert_equal 'false', %q{
  class Foo
    attr_reader :exception

    def failed?
      !exception.nil?
    end
  end

  foo = Foo.new.freeze
  foo.failed?
  foo.failed?
}

# regression test for doing kwarg shuffle before checking for interrupts
assert_equal 'ok', %q{
  def new_media_drop(attributes:, product_drop:, context:, sources:)
    nil.nomethod rescue nil # force YJIT to bail to side exit

    [attributes, product_drop, context, sources]
  end

  def load_medias(product_drop: nil, raw_medias:, context:)
    raw_medias.map do |raw_media|
      case new_media_drop(context: context, attributes: raw_media, product_drop: product_drop, sources: [])
      in [Hash, ProductDrop, Context, Array]
      else
        raise "bad shuffle"
      end
    end
  end

  class Context; end

  class ProductDrop
    attr_reader :title
    def initialize(title)
      @title = title
    end
  end

  # Make a thread so we have thread switching interrupts
  th = Thread.new do
    while true; end
  end
  1_000.times do |i|
    load_medias(product_drop: ProductDrop.new("foo"), raw_medias: [{}, {}], context: Context.new)
  end
  th.kill.join

  :ok
}

# regression test for tracing attr_accessor methods.
assert_equal "true", %q{
    c = Class.new do
      attr_accessor :x
      alias y x
      alias y= x=
    end
    obj = c.new

    ar_meth = obj.method(:x)
    aw_meth = obj.method(:x=)
    aar_meth = obj.method(:y)
    aaw_meth = obj.method(:y=)
    events = []
    trace = TracePoint.new(:c_call, :c_return){|tp|
      next if tp.path != __FILE__
      next if tp.method_id == :call
      case tp.event
      when :c_call
        events << [tp.event, tp.method_id, tp.callee_id]
      when :c_return
        events << [tp.event, tp.method_id, tp.callee_id, tp.return_value]
      end
    }
    test_proc = proc do
      obj.x = 1
      obj.x
      obj.y = 2
      obj.y
      aw_meth.call(1)
      ar_meth.call
      aaw_meth.call(2)
      aar_meth.call
    end
    test_proc.call # populate call caches
    trace.enable(&test_proc)
    expected = [
      [:c_call, :x=, :x=],
      [:c_return, :x=, :x=, 1],
      [:c_call, :x, :x],
      [:c_return, :x, :x, 1],
      [:c_call, :x=, :y=],
      [:c_return, :x=, :y=, 2],
      [:c_call, :x, :y],
      [:c_return, :x, :y, 2],
    ] * 2

    expected == events
}

# duphash
assert_equal '{foo: 123}', %q{
  def foo
    {foo: 123}
  end

  foo
  foo
}

# newhash
assert_equal '{foo: 2}', %q{
  def foo
    {foo: 1+1}
  end

  foo
  foo
}

# block invalidation edge case
assert_equal 'undef', %q{
  class A
    def foo(arg)
      arg.times { A.remove_method(:bar) }
      self
    end

    def bar
      4
    end

    def use(arg)
      # two consecutive sends. When bar is removed, the return address
      # for calling it is already on foo's control frame
      foo(arg).bar
    rescue NoMethodError
      :undef
    end
  end

  A.new.use 0
  A.new.use 0
  A.new.use 1
}

# block invalidation edge case
assert_equal 'ok', %q{
  class A
    Good = :ng
    def foo(arg)
      arg.times { A.const_set(:Good, :ok) }
      self
    end

    def id(arg)
      arg
    end

    def use(arg)
      # send followed by an opt_getinlinecache.
      # The return address remains on the control frame
      # when opt_getinlinecache is invalidated.
      foo(arg).id(Good)
    end
  end

  A.new.use 0
  A.new.use 0
  A.new.use 1
}

assert_equal 'ok', %q{
  # test hitting a branch stub when out of memory
  def nimai(jita)
    if jita
      :ng
    else
      :ok
    end
  end

  nimai(true)
  nimai(true)

  RubyVM::YJIT.simulate_oom! if defined?(RubyVM::YJIT)

  nimai(false)
}

assert_equal 'new', %q{
  # test block invalidation while out of memory
  def foo
    :old
  end

  def test
    foo
  end

  def bar
    :bar
  end


  test
  test

  RubyVM::YJIT.simulate_oom! if defined?(RubyVM::YJIT)

  # Old simulat_omm! leaves one byte of space and this fills it up
  bar
  bar

  def foo
    :new
  end

  test
}

# Bug #21257 (infinite jmp)
assert_equal 'ok', %q{
  Good = :ok

  def first
    second
  end

  def second
    ::Good
  end

  # Make `second` side exit on its first instruction
  trace = TracePoint.new(:line) { }
  trace.enable(target: method(:second))

  first
  # Recompile now that the constant cache is populated, so we get a fallthrough from `first` to `second`
  # (this is need to reproduce with --yjit-call-threshold=1)
  RubyVM::YJIT.code_gc if defined?(RubyVM::YJIT)
  first

  # Trigger a constant cache miss in rb_vm_opt_getconstant_path (in `second`) next time it's called
  module InvalidateConstantCache
    Good = nil
  end

  RubyVM::YJIT.simulate_oom! if defined?(RubyVM::YJIT)

  first
  first
}

assert_equal 'ok', %q{
  # Try to compile new method while OOM
  def foo
    :ok
  end

  RubyVM::YJIT.simulate_oom! if defined?(RubyVM::YJIT)

  foo
  foo
}

# struct aref embedded
assert_equal '2', %q{
  def foo(s)
    s.foo
  end

  S = Struct.new(:foo)
  foo(S.new(1))
  foo(S.new(2))
}

# struct aref non-embedded
assert_equal '4', %q{
  def foo(s)
    s.d
  end

  S = Struct.new(:a, :b, :c, :d, :e)
  foo(S.new(1,2,3,4,5))
  foo(S.new(1,2,3,4,5))
}

# struct aset embedded
assert_equal '123', %q{
  def foo(s)
    s.foo = 123
  end

  s = Struct.new(:foo).new
  foo(s)
  s = Struct.new(:foo).new
  foo(s)
  s.foo
}

# struct aset non-embedded
assert_equal '[1, 2, 3, 4, 5]', %q{
  def foo(s)
    s.a = 1
    s.b = 2
    s.c = 3
    s.d = 4
    s.e = 5
  end

  S = Struct.new(:a, :b, :c, :d, :e)
  s = S.new
  foo(s)
  s = S.new
  foo(s)
  [s.a, s.b, s.c, s.d, s.e]
}

# struct aref too many args
assert_equal 'ok', %q{
  def foo(s)
    s.foo(:bad)
  end

  s = Struct.new(:foo).new
  foo(s) rescue :ok
  foo(s) rescue :ok
}

# struct aset too many args
assert_equal 'ok', %q{
  def foo(s)
    s.set_foo(123, :bad)
  end

  s = Struct.new(:foo) do
    alias :set_foo :foo=
  end
  foo(s) rescue :ok
  foo(s) rescue :ok
}

# File.join is a cfunc accepting variable arguments as a Ruby array (argc = -2)
assert_equal 'foo/bar', %q{
  def foo
    File.join("foo", "bar")
  end

  foo
  foo
}

# File.join is a cfunc accepting variable arguments as a Ruby array (argc = -2)
assert_equal '', %q{
  def foo
    File.join()
  end

  foo
  foo
}

# Make sure we're correctly reading RStruct's as.ary union for embedded RStructs
assert_equal '3,12', %q{
  pt_struct = Struct.new(:x, :y)
  p = pt_struct.new(3, 12)
  def pt_inspect(pt)
    "#{pt.x},#{pt.y}"
  end

  # Make sure pt_inspect is JITted
  10.times { pt_inspect(p) }

  # Make sure it's returning '3,12' instead of e.g. '3,false'
  pt_inspect(p)
}

# Regression test for deadlock between branch_stub_hit and ractor_receive_if
assert_equal '10', %q{
  r = Ractor.new Ractor.current do |main|
    main << 1
    main << 2
    main << 3
    main << 4
    main << 5
    main << 6
    main << 7
    main << 8
    main << 9
    main << 10
  end

  a = []
  a << Ractor.receive_if{|msg| msg == 10}
  a << Ractor.receive_if{|msg| msg == 9}
  a << Ractor.receive_if{|msg| msg == 8}
  a << Ractor.receive_if{|msg| msg == 7}
  a << Ractor.receive_if{|msg| msg == 6}
  a << Ractor.receive_if{|msg| msg == 5}
  a << Ractor.receive_if{|msg| msg == 4}
  a << Ractor.receive_if{|msg| msg == 3}
  a << Ractor.receive_if{|msg| msg == 2}
  a << Ractor.receive_if{|msg| msg == 1}

  a.length
}

# checktype
assert_equal 'false', %q{
    def function()
        [1, 2] in [Integer, String]
    end
    function()
}

# opt_send_without_block (VM_METHOD_TYPE_ATTRSET)
assert_equal 'foo', %q{
    class Foo
      attr_writer :foo

      def foo()
        self.foo = "foo"
      end
    end
    foo = Foo.new
    foo.foo
}

# anytostring, intern
assert_equal 'true', %q{
    def foo()
      :"#{true}"
    end
    foo()
}

# toregexp, objtostring
assert_equal '/true/', %q{
    def foo()
      /#{true}/
    end
    foo().inspect
}

# concatstrings, objtostring
assert_equal '9001', %q{
    def foo()
      "#{9001}"
    end
    foo()
}

# opt_send_without_block (VM_METHOD_TYPE_CFUNC)
assert_equal 'nil', %q{
    def foo
      nil.inspect # argc: 0
    end
    foo
}
assert_equal '4', %q{
    def foo
      2.pow(2) # argc: 1
    end
    foo
}
assert_equal 'aba', %q{
    def foo
      "abc".tr("c", "a") # argc: 2
    end
    foo
}
assert_equal 'true', %q{
    def foo
      respond_to?(:inspect) # argc: -1
    end
    foo
}
assert_equal '["a", "b"]', %q{
    def foo
      "a\nb".lines(chomp: true) # kwargs
    end
    foo
}

# invokebuiltin
assert_equal '123', %q{
  def foo(obj)
    obj.foo = 123
  end

  struct = Struct.new(:foo)
  obj = struct.new
  foo(obj)
}

# invokebuiltin_delegate
assert_equal '.', %q{
  def foo(path)
    Dir.open(path).path
  end
  foo(".")
}

# opt_invokebuiltin_delegate_leave
assert_equal '[0]', %q{"\x00".unpack("c")}

# opt_send_without_block (VM_METHOD_TYPE_ISEQ)
assert_equal '1', %q{
  def foo = 1
  def bar = foo
  bar
}
assert_equal '[1, 2, 3]', %q{
  def foo(a, b) = [1, a, b]
  def bar = foo(2, 3)
  bar
}
assert_equal '[1, 2, 3, 4, 5, 6]', %q{
  def foo(a, b, c:, d:, e: 0, f: 6) = [a, b, c, d, e, f]
  def bar = foo(1, 2, c: 3, d: 4, e: 5)
  bar
}
assert_equal '[1, 2, 3, 4]', %q{
  def foo(a, b = 2) = [a, b]
  def bar = foo(1) + foo(3, 4)
  bar
}

assert_equal '1', %q{
  def foo(a) = a
  def bar = foo(1) { 2 }
  bar
}
assert_equal '[1, 2]', %q{
  def foo(a, &block) = [a, block.call]
  def bar = foo(1) { 2 }
  bar
}

# opt_send_without_block (VM_METHOD_TYPE_IVAR)
assert_equal 'foo', %q{
  class Foo
    attr_reader :foo

    def initialize
      @foo = "foo"
    end
  end
  Foo.new.foo
}

# opt_send_without_block (VM_METHOD_TYPE_OPTIMIZED)
assert_equal 'foo', %q{
  Foo = Struct.new(:bar)
  Foo.new("bar").bar = "foo"
}
assert_equal 'foo', %q{
  Foo = Struct.new(:bar)
  Foo.new("foo").bar
}

# getblockparamproxy
assert_equal 'foo', %q{
  def foo(&block)
    block.call
  end
  foo { "foo" }
}

# getblockparam
assert_equal 'foo', %q{
  def foo(&block)
    block
  end
  foo { "foo" }.call
}

assert_equal '[1, 2]', %q{
  def foo
    x = [2]
    [1, *x]
  end

  foo
  foo
}

# respond_to? with changing symbol
assert_equal 'false', %q{
  def foo(name)
    :sym.respond_to?(name)
  end
  foo(:to_s)
  foo(:to_s)
  foo(:not_exist)
}

# respond_to? with method being defined
assert_equal 'true', %q{
  def foo
    :sym.respond_to?(:not_yet_defined)
  end
  foo
  foo
  module Kernel
    def not_yet_defined = true
  end
  foo
}

# respond_to? with undef method
assert_equal 'false', %q{
  module Kernel
    def to_be_removed = true
  end
  def foo
    :sym.respond_to?(:to_be_removed)
  end
  foo
  foo
  class Object
    undef_method :to_be_removed
  end
  foo
}

# respond_to? with respond_to_missing?
assert_equal 'true', %q{
  class Foo
  end
  def foo(x)
    x.respond_to?(:bar)
  end
  foo(Foo.new)
  foo(Foo.new)
  class Foo
    def respond_to_missing?(*) = true
  end
  foo(Foo.new)
}

# bmethod
assert_equal '[1, 2, 3]', %q{
  one = 1
  define_method(:foo) do
    one
  end

  3.times.map { |i| foo + i }
}

# return inside bmethod
assert_equal 'ok', %q{
  define_method(:foo) do
    1.tap { return :ok }
  end

  foo
}

# bmethod optional and keywords
assert_equal '[[1, nil, 2]]', %q{
  define_method(:opt_and_kwargs) do |a = {}, b: nil, c: nil|
    [a, b, c]
  end

  5.times.map { opt_and_kwargs(1, c: 2) }.uniq
}

# bmethod with forwarded block
assert_equal '2', %q{
  define_method(:foo) do |&block|
    block.call
  end

  def bar(&block)
    foo(&block)
  end

  bar { 1 }
  bar { 2 }
}

# bmethod with forwarded block and arguments
assert_equal '5', %q{
  define_method(:foo) do |n, &block|
    n + block.call
  end

  def bar(n, &block)
    foo(n, &block)
  end

  bar(0) { 1 }
  bar(3) { 2 }
}

# bmethod with forwarded unwanted block
assert_equal '1', %q{
  one = 1
  define_method(:foo) do
    one
  end

  def bar(&block)
    foo(&block)
  end

  bar { }
  bar { }
}

# test for return stub lifetime issue
assert_equal '1', %q{
  def foo(n)
    if n == 2
      return 1.times { Object.define_method(:foo) {} }
    end

    foo(n + 1)
  end

  foo(1)
}

# case-when with redefined ===
assert_equal 'ok', %q{
  class Symbol
    def ===(a)
      true
    end
  end

  def cw(arg)
    case arg
    when :b
      :ok
    when 4
      :ng
    end
  end

  cw(4)
}

assert_equal 'threw', %q{
  def foo(args)
    wrap(*args)
  rescue ArgumentError
    'threw'
  end

  def wrap(a)
    [a]
  end

  foo([Hash.ruby2_keywords_hash({})])
}

assert_equal 'threw', %q{
  # C call
  def bar(args)
    Array(*args)
  rescue ArgumentError
    'threw'
  end

  bar([Hash.ruby2_keywords_hash({})])
}

# Test instance_of? and is_a?
assert_equal 'true', %q{
  1.instance_of?(Integer) && 1.is_a?(Integer)
}

# Test instance_of? and is_a? for singleton classes
assert_equal 'true', %q{
  a = []
  def a.test = :test
  a.instance_of?(Array) && a.is_a?(Array)
}

# Test instance_of? for singleton_class
# Yes this does really return false
assert_equal 'false', %q{
  a = []
  def a.test = :test
  a.instance_of?(a.singleton_class)
}

# Test is_a? for singleton_class
assert_equal 'true', %q{
  a = []
  def a.test = :test
  a.is_a?(a.singleton_class)
}

# Test send with splat to a cfunc
assert_equal 'true', %q{
  1.send(:==, 1, *[])
}

# Test empty splat with cfunc
assert_equal '2', %q{
  def foo
    Integer.sqrt(4, *[])
  end
  # call twice to deal with constant exiting
  foo
  foo
}

# Test non-empty splat with cfunc
assert_equal 'Hello World', %q{
  def bar
    args = ["Hello "]
    greeting = +"World"
    greeting.insert(0, *args)
    greeting
  end
  bar
}

# Regression: this creates a temp stack with > 127 elements
assert_normal_exit %q{
  def foo(a)
    [
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a,
    ]
  end

  def entry
    foo(1)
  end

  entry
}

# Test that splat and rest combined
# properly dupe the array
assert_equal "[]", %q{
  def foo(*rest)
    rest << 1
  end

  def test(splat)
    foo(*splat)
  end

  EMPTY = []
  custom = Object.new
  def custom.to_a
    EMPTY
  end

  test(custom)
  test(custom)
  EMPTY
}

# Rest with send
assert_equal '[1, 2, 3]', %q{
  def bar(x, *rest)
    rest.insert(0, x)
  end
  send(:bar, 1, 2, 3)
}

# Fix splat block arg bad compilation
assert_equal "foo", %q{
  def literal(*args, &block)
    s = ''.dup
    literal_append(s, *args, &block)
    s
  end

  def literal_append(sql, v)
    sql << v
  end

  literal("foo")
}

# regression test for accidentally having a parameter truncated
# due to Rust/C signature mismatch. Used to crash with
# > [BUG] rb_vm_insn_addr2insn: invalid insn address ...
# or
# > ... `Err` value: TryFromIntError(())'
assert_normal_exit %q{
  n = 16384
  eval(
    "def foo(arg); " + "_=arg;" * n + '_=1;' + "Object; end"
  )
  foo 1
}

# Regression test for CantCompile not using starting_ctx
assert_normal_exit %q{
  class Integer
    def ===(other)
      false
    end
  end

  def my_func(x)
    case x
    when 1
      1
    when 2
      2
    else
      3
    end
  end

  my_func(1)
}

# Regression test for CantCompile not using starting_ctx
assert_equal "ArgumentError", %q{
  def literal(*args, &block)
    s = ''.dup
    args = [1, 2, 3]
    literal_append(s, *args, &block)
    s
  end

  def literal_append(sql, v)
    [sql.inspect, v.inspect]
  end

  begin
    literal("foo")
  rescue ArgumentError
    "ArgumentError"
  end
}

# Rest with block
# Simplified code from railsbench
assert_equal '[{"/a" => "b", as: :c, via: :post}, [], nil]', %q{
  def match(path, *rest, &block)
    [path, rest, block]
  end

  def map_method(method, args, &block)
    options = args.last
    args.pop
    options[:via] = method
    match(*args, options, &block)
  end

  def post(*args, &block)
    map_method(:post, args, &block)
  end

  post "/a" => "b", as: :c
}

# Test rest and kw_args
assert_equal '[true, true, true, true]', %q{
  def my_func(*args, base: nil, sort: true)
    [args, base, sort]
  end

  def calling_my_func
    results = []
    results << (my_func("test") == [["test"], nil, true])
    results << (my_func("test", base: :base) == [["test"], :base, true])
    results << (my_func("test", sort: false) == [["test"], nil, false])
    results << (my_func("test", "other", base: :base) == [["test", "other"], :base, true])
    results
  end
  calling_my_func
}

# Test Integer#[] with 2 args
assert_equal '0', %q{
  3[0, 0]
}

# unspecified_bits + checkkeyword
assert_equal '2', %q{
  def callee = 1

  # checkkeyword should see unspecified_bits=0 (use bar), not Integer 1 (set bar = foo).
  def foo(foo, bar: foo) = bar

  def entry(&block)
    # write 1 at stack[3]. Calling #callee spills stack[3].
    1 + (1 + (1 + (1 + callee)))
    # &block is written to a register instead of stack[3]. When &block is popped and
    # unspecified_bits is pushed, it must be written to stack[3], not to a register.
    foo(1, bar: 2, &block)
  end

  entry # call branch_stub_hit (spill temps)
  entry # doesn't call branch_stub_hit (not spill temps)
}

# Test rest and optional_params
assert_equal '[true, true, true, true]', %q{
  def my_func(stuff, base=nil, sort=true, *args)
    [stuff, base, sort, args]
  end

  def calling_my_func
    results = []
    results << (my_func("test") == ["test", nil, true, []])
    results << (my_func("test", :base) == ["test", :base, true, []])
    results << (my_func("test", :base, false) == ["test", :base, false, []])
    results << (my_func("test", :base, false, "other", "other") == ["test", :base, false, ["other", "other"]])
    results
  end
  calling_my_func
}

# Test rest and optional_params and splat
assert_equal '[true, true, true, true, true]', %q{
  def my_func(stuff, base=nil, sort=true, *args)
    [stuff, base, sort, args]
  end

  def calling_my_func
    results = []
    splat = ["test"]
    results << (my_func(*splat) == ["test", nil, true, []])
    splat = [:base]
    results << (my_func("test", *splat) == ["test", :base, true, []])
    splat = [:base, false]
    results << (my_func("test", *splat) == ["test", :base, false, []])
    splat = [:base, false, "other", "other"]
    results << (my_func("test", *splat) == ["test", :base, false, ["other", "other"]])
    splat = ["test", :base, false, "other", "other"]
    results << (my_func(*splat) == ["test", :base, false, ["other", "other"]])
    results
  end
  calling_my_func
}

# Regression test: rest and optional and splat
assert_equal 'true', %q{
  def my_func(base=nil, *args)
    [base, args]
  end

  def calling_my_func
    array = []
    my_func(:base, :rest1, *array) == [:base, [:rest1]]
  end

  calling_my_func
}

# Fix failed case for large splat
assert_equal 'true', %q{
  def d(a, b=:b)
  end

  def calling_func
    ary = 1380888.times;
    d(*ary)
  end
  begin
    calling_func
  rescue ArgumentError
    true
  end
}

# Regression test: register allocator on expandarray
assert_equal '[]', %q{
  func = proc { [] }
  proc do
    _x, _y = func.call
  end.call
}

# Catch TAG_BREAK in a non-FINISH frame with JIT code
assert_equal '1', %q{
  def entry
    catch_break
  end

  def catch_break
    while_true do
      break
    end
    1
  end

  def while_true
    while true
      yield
    end
  end

  entry
}

assert_equal '6', %q{
  class Base
    def number = 1 + yield
  end

  class Sub < Base
    def number = super + 2
  end

  Sub.new.number { 3 }
}

# Integer multiplication and overflow
assert_equal '[6, -6, 9671406556917033397649408, -9671406556917033397649408, 21267647932558653966460912964485513216]', %q{
  def foo(a, b)
    a * b
  end

  r1 = foo(2, 3)
  r2 = foo(2, -3)
  r3 = foo(2 << 40, 2 << 41)
  r4 = foo(2 << 40, -2 << 41)
  r5 = foo(1 << 62, 1 << 62)

  [r1, r2, r3, r4, r5]
}

# Integer multiplication and overflow (minimized regression test from test-basic)
assert_equal '8515157028618240000', %q{2128789257154560000 * 4}

# Inlined method calls
assert_equal 'nil', %q{
  def putnil = nil
  def entry = putnil
  entry.inspect
}
assert_equal '1', %q{
  def putobject_1 = 1
  def entry = putobject_1
  entry
}
assert_equal 'false', %q{
  def putobject(_unused_arg1) = false
  def entry = putobject(nil)
  entry
}
assert_equal 'true', %q{
  def entry = yield
  entry { true }
}
assert_equal 'sym', %q{
  def entry = :sym.to_sym
  entry
}

assert_normal_exit %q{
  ivars = 1024.times.map { |i| "@iv_#{i} = #{i}\n" }.join
  Foo = Class.new
  Foo.class_eval "def initialize() #{ivars} end"
  Foo.new
}

assert_equal '0', %q{
  def spill
    1.to_i # not inlined
  end

  def inline(_stack1, _stack2, _stack3, _stack4, _stack5)
    0 # inlined
  end

  def entry
    # RegTemps is 00111110 prior to the #inline call.
    # Its return value goes to stack_idx=0, which conflicts with stack_idx=5.
    inline(spill, 2, 3, 4, 5)
  end

  entry
}

# Integer succ and overflow
assert_equal '[2, 4611686018427387904]', %q{
  [1.succ, 4611686018427387903.succ]
}

# Integer pred and overflow
assert_equal '[0, -4611686018427387905]', %q{
  [1.pred, -4611686018427387904.pred]
}

# Integer right shift
assert_equal '[0, 1, -4]', %q{
  [0 >> 1, 2 >> 1, -7 >> 1]
}

# Integer XOR
assert_equal '[0, 0, 4]', %q{
  [0 ^ 0, 1 ^ 1, 7 ^ 3]
}

assert_equal '[nil, "yield"]', %q{
  def defined_yield = defined?(yield)
  [defined_yield, defined_yield {}]
}

# splat with ruby2_keywords into rest parameter
assert_equal '[[{a: 1}], {}]', %q{
  ruby2_keywords def foo(*args) = args

  def bar(*args, **kw) = [args, kw]

  def pass_bar(*args) = bar(*args)

  def body
    args = foo(a: 1)
    pass_bar(*args)
  end

  body
}

# concatarray
assert_equal '[1, 2]', %q{
  def foo(a, b) = [a, b]
  arr = [2]
  foo(*[1], *arr)
}

# pushtoarray
assert_equal '[1, 2]', %q{
  def foo(a, b) = [a, b]
  arr = [1]
  foo(*arr, 2)
}

# pop before fallback
assert_normal_exit %q{
  class Foo
    attr_reader :foo

    def try = foo(0, &nil)
  end

  Foo.new.try
}

# a kwrest case
assert_equal '[1, 2, {complete: false}]', %q{
  def rest(foo: 1, bar: 2, **kwrest)
    [foo, bar, kwrest]
  end

  def callsite = rest(complete: false)

  callsite
}

# splat+kw_splat+opt+rest
assert_equal '[1, []]', %q{
  def opt_rest(a = 0, *rest) = [a, rest]

  def call_site(args) = opt_rest(*args, **nil)

  call_site([1])
}

# splat and nil kw_splat
assert_equal 'ok', %q{
  def identity(x) = x

  def splat_nil_kw_splat(args) = identity(*args, **nil)

  splat_nil_kw_splat([:ok])
}

# empty splat and kwsplat into leaf builtins
assert_equal '[1, 1, 1]', %q{
  empty = []
  [1.abs(*empty), 1.abs(**nil), 1.bit_length(*empty, **nil)]
}

# splat into C methods with -1 arity
assert_equal '[[1, 2, 3], [0, 2, 3], [1, 2, 3], [2, 2, 3], [], [], [{}]]', %q{
  class Foo < Array
    def push(args) = super(1, *args)
  end

  def test_cfunc_vargs_splat(sub_instance, array_class, empty_kw_hash)
    splat = [2, 3]
    kw_splat = [empty_kw_hash]
    [
      sub_instance.push(splat),
      array_class[0, *splat, **nil],
      array_class[1, *splat, &nil],
      array_class[2, *splat, **nil, &nil],
      array_class.send(:[], *kw_splat),
      # kw_splat disables keywords hash handling
      array_class[*kw_splat],
      array_class[*kw_splat, **nil],
    ]
  end

  test_cfunc_vargs_splat(Foo.new, Array, Hash.ruby2_keywords_hash({}))
}

# Class#new (arity=-1), splat, and ruby2_keywords
assert_equal '[0, {1 => 1}]', %q{
  class KwInit
    attr_reader :init_args
    def initialize(x = 0, **kw)
      @init_args = [x, kw]
    end
  end

  def test(klass, args)
    klass.new(*args).init_args
  end

  test(KwInit, [Hash.ruby2_keywords_hash({1 => 1})])
}

# Chilled string setivar trigger warning
assert_match(/literal string will be frozen in the future/, %q{
  Warning[:deprecated] = true
  $VERBOSE = true
  $warning = "no-warning"
  module ::Warning
    def self.warn(message)
      $warning = message.split("warning: ").last.strip
    end
  end

  class String
    def setivar!
      @ivar = 42
    end
  end

  def setivar!(str)
    str.setivar!
  end

  10.times { setivar!("mutable".dup) }
  10.times do
    setivar!("frozen".freeze)
  rescue FrozenError
  end

  setivar!("chilled") # Emit warning
  $warning
})

# arity=-2 cfuncs
assert_equal '["", "1/2", [0, [:ok, 1]]]', %q{
  def test_cases(file, chain)
    new_chain = chain.allocate # to call initialize directly
    new_chain.send(:initialize, [0], ok: 1)

    [
      file.join,
      file.join("1", "2"),
      new_chain.to_a,
    ]
  end

  test_cases(File, Enumerator::Chain)
}

# singleton class should invalidate Type::CString assumption
assert_equal 'foo', %q{
  def define_singleton(str, define)
    if define
      # Wrap a C method frame to avoid exiting JIT code on defineclass
      [nil].reverse_each do
        class << str
          def +(_)
            "foo"
          end
        end
      end
    end
    "bar"
  end

  def entry(define)
    str = ""
    # When `define` is false, #+ compiles to rb_str_plus() without a class guard.
    # When the code is reused with `define` is true, the class of `str` is changed
    # to a singleton class, so the block should be invalidated.
    str + define_singleton(str, define)
  end

  entry(false)
  entry(true)
}

assert_equal 'ok', %q{
  def ok
    :ok
  end

  def delegator(...)
    ok(...)
  end

  def caller
    send(:delegator)
  end

  caller
}

# test inlining of simple iseqs
assert_equal '[:ok, :ok, :ok]', %q{
  def identity(x) = x
  def foo(x, _) = x
  def bar(_, _, _, _, x) = x

  def tests
    [
      identity(:ok),
      foo(:ok, 2),
      bar(1, 2, 3, 4, :ok),
    ]
  end

  tests
}

# test inlining of simple iseqs with kwargs
assert_equal '[:ok, :ok, :ok, :ok, :ok]', %q{
  def optional_unused(x, opt: :not_ok) = x
  def optional_used(x, opt: :ok) = opt
  def required_unused(x, req:) = x
  def required_used(x, req:) = req
  def unknown(x) = x

  def tests
    [
      optional_unused(:ok),
      optional_used(:not_ok),
      required_unused(:ok, req: :not_ok),
      required_used(:not_ok, req: :ok),
      begin unknown(:not_ok, unknown_kwarg: :not_ok) rescue ArgumentError; :ok end,
    ]
  end

  tests
}

# test simple iseqs not eligible for inlining
assert_equal '[:ok, :ok, :ok, :ok, :ok]', %q{
  def identity(x) = x
  def arg_splat(x, *args) = x
  def kwarg_splat(x, **kwargs) = x
  def block_arg(x, &blk) = x
  def block_iseq(x) = x
  def call_forwarding(...) = identity(...)

  def tests
    [
      arg_splat(:ok),
      kwarg_splat(:ok),
      block_arg(:ok, &proc { :not_ok }),
      block_iseq(:ok) { :not_ok },
      call_forwarding(:ok),
    ]
  end

  tests
}

# regression test for invalidating an empty block
assert_equal '0', %q{
  def foo = (* = 1).pred

  foo # compile it

  class Integer
    def to_ary = [] # invalidate
  end

  foo # try again
}

# test integer left shift with constant rhs
assert_equal [0x80000000000, 'a+', :ok].inspect, %q{
  def shift(val) = val << 43

  def tests
    int = shift(1)
    str = shift("a")

    Integer.define_method(:<<) { |_| :ok }
    redef = shift(1)

    [int, str, redef]
  end

  tests
}

# test integer left shift fusion followed by opt_getconstant_path
assert_equal '33', %q{
  def test(a)
    (a << 5) | (Object; a)
  end

  test(1)
}

# test String#stebyte with arguments that need conversion
assert_equal "abc", %q{
  str = +"a00"
  def change_bytes(str, one, two)
    str.setbyte(one, "b".ord)
    str.setbyte(2, two)
  end

  to_int_1 = Object.new
  to_int_99 = Object.new
  def to_int_1.to_int = 1
  def to_int_99.to_int = 99

  change_bytes(str, to_int_1, to_int_99)
  str
}

# test --yjit-verify-ctx for arrays with a singleton class
assert_equal "ok", %q{
  class Array
    def foo
      self.singleton_class.define_method(:first) { :ok }
      first
    end
  end

  def test = [].foo

  test
}

assert_equal '["raised", "Module", "Object"]', %q{
  def foo(obj)
    obj.superclass.name
  end

  ret = []

  begin
    foo(Class.allocate)
  rescue TypeError
    ret << 'raised'
  end

  ret += [foo(Class), foo(Class.new)]
}

# test TrueClass#=== before and after redefining TrueClass#==
assert_equal '[[true, false, false], [true, true, false], [true, :error, :error]]', %q{
  def true_eqq(x)
    true === x
  rescue NoMethodError
    :error
  end

  def test
    [
      # first one is always true because rb_equal does object comparison before calling #==
      true_eqq(true),
      # these will use TrueClass#==
      true_eqq(false),
      true_eqq(:truthy),
    ]
  end

  results = [test]

  class TrueClass
    def ==(x)
      !x
    end
  end

  results << test

  class TrueClass
    undef_method :==
  end

  results << test
}

# test FalseClass#=== before and after redefining FalseClass#==
assert_equal '[[true, false, false], [true, false, true], [true, :error, :error]]', %q{
  def case_equal(x, y)
    x === y
  rescue NoMethodError
    :error
  end

  def test
    [
      # first one is always true because rb_equal does object comparison before calling #==
      case_equal(false, false),
      # these will use #==
      case_equal(false, true),
      case_equal(false, nil),
    ]
  end

  results = [test]

  class FalseClass
    def ==(x)
      !x
    end
  end

  results << test

  class FalseClass
    undef_method :==
  end

  results << test
}

# test NilClass#=== before and after redefining NilClass#==
assert_equal '[[true, false, false], [true, false, true], [true, :error, :error]]', %q{
  def case_equal(x, y)
    x === y
  rescue NoMethodError
    :error
  end

  def test
    [
      # first one is always true because rb_equal does object comparison before calling #==
      case_equal(nil, nil),
      # these will use #==
      case_equal(nil, true),
      case_equal(nil, false),
    ]
  end

  results = [test]

  class NilClass
    def ==(x)
      !x
    end
  end

  results << test

  class NilClass
    undef_method :==
  end

  results << test
}

# test struct accessors fire c_call events
assert_equal '[[:c_call, :x=], [:c_call, :x]]', %q{
  c = Struct.new(:x)
  obj = c.new

  events = []
  TracePoint.new(:c_call) do
    events << [_1.event, _1.method_id]
  end.enable do
    obj.x = 100
    obj.x
  end

  events
}

# regression test for splatting empty array
assert_equal '1', %q{
  def callee(foo) = foo

  def test_body(args) = callee(1, *args)

  test_body([])
  array = Array.new(100)
  array.clear
  test_body(array)
}

# regression test for splatting empty array to cfunc
assert_normal_exit %q{
  def test_body(args) = Array(1, *args)

  test_body([])
  0x100.times do
    array = Array.new(100)
    array.clear
    test_body(array)
  end
}

# compiling code shouldn't emit warnings as it may call into more Ruby code
assert_equal 'ok', <<~'RUBY'
  # [Bug #20522]
  $VERBOSE = true
  Warning[:performance] = true

  module StrictWarnings
    def warn(msg, **)
      raise msg
    end
  end
  Warning.singleton_class.prepend(StrictWarnings)

  class A
    def compiled_method(is_private)
      @some_ivar = is_private
    end
  end

  shape_max_variations = 8
  if defined?(RubyVM::Shape::SHAPE_MAX_VARIATIONS) && RubyVM::Shape::SHAPE_MAX_VARIATIONS != shape_max_variations
    raise "Expected SHAPE_MAX_VARIATIONS to be #{shape_max_variations}, got: #{RubyVM::Shape::SHAPE_MAX_VARIATIONS}"
  end

  100.times do |i|
    klass = Class.new(A)
    (shape_max_variations - 1).times do |j|
      obj = klass.new
      obj.instance_variable_set("@base_#{i}", 42)
      obj.instance_variable_set("@ivar_#{j}", 42)
    end
    obj = klass.new
    obj.instance_variable_set("@base_#{i}", 42)
    begin
      obj.compiled_method(true)
    rescue
      # expected
    end
  end

  :ok
RUBY

assert_equal 'ok', <<~'RUBY'
  class MyRelation
    def callee(...)
      :ok
    end

    def uncached(...)
      callee(...)
    end

    def takes_block(&block)
      # push blockhandler
      uncached(&block) # CI1
    end
  end

  relation = MyRelation.new
  relation.takes_block { }
RUBY

assert_equal 'ok', <<~'RUBY'
  def _exec_scope(...)
    instance_exec(...)
  end

  def ok args, body
    _exec_scope(*args, &body)
  end

  ok([], -> { "ok" })
RUBY

assert_equal 'ok', <<~'RUBY'
  def _exec_scope(...)
    instance_exec(...)
  end

  def ok args, body
    _exec_scope(*args, &body)
  end

  ok(["ok"], ->(x) { x })
RUBY

assert_equal 'ok', <<~'RUBY'
def baz(a, b)
  a + b
end

def bar(...)
  baz(...)
end

def foo(a, ...)
  bar(a, ...)
end

def test
  foo("o", "k")
end

test
RUBY

# opt_newarray_send pack/buffer
assert_equal '[true, true]', <<~'RUBY'
  def pack
    v = 1.23
    [v, v*2, v*3].pack("E*").unpack("E*") == [v, v*2, v*3]
  end

  def with_buffer
    v = 4.56
    b = +"x"
    [v, v*2, v*3].pack("E*", buffer: b)
    b[1..].unpack("E*") == [v, v*2, v*3]
  end

  [pack, with_buffer]
RUBY

# String#[] / String#slice
assert_equal 'ok', <<~'RUBY'
  def error(klass)
    yield
  rescue klass
    true
  end

  def test
    str = "こんにちは"
    substr = "にち"
    failures = []

    # Use many small statements to keep context for each slice call smaller than MAX_CTX_TEMPS

    str[1] == "ん" && str.slice(4) == "は" || failures << :index
    str[5].nil? && str.slice(5).nil? || failures << :index_end

    str[1, 2] == "んに" && str.slice(2, 1) == "に" || failures << :beg_len
    str[5, 1] == "" && str.slice(5, 1) == "" || failures << :beg_len_end

    str[1..2] == "んに" && str.slice(2..2) == "に" || failures << :range

    str[/に./] == "にち" && str.slice(/に./) == "にち" || failures << :regexp

    str[/に./, 0] == "にち" && str.slice(/に./, 0) == "にち" || failures << :regexp_cap0

    str[/に(.)/, 1] == "ち" && str.slice(/に(.)/, 1) == "ち" || failures << :regexp_cap1

    str[substr] == substr && str.slice(substr) == substr || failures << :substr

    error(TypeError) { str[Object.new] } && error(TypeError) { str.slice(Object.new, 1) } || failures << :type_error
    error(RangeError) { str[Float::INFINITY] } && error(RangeError) { str.slice(Float::INFINITY) } || failures << :range_error

    return "ok" if failures.empty?
    {failures: failures}
  end

  test
RUBY

# opt_duparray_send :include?
assert_equal '[true, false]', <<~'RUBY'
  def test(x)
    [:a, :b].include?(x)
  end

  [
    test(:b),
    test(:c),
  ]
RUBY

# opt_newarray_send :include?
assert_equal '[true, false]', <<~'RUBY'
  def test(x)
    [Object.new, :a, :b].include?(x.to_sym)
  end

  [
    test("b"),
    test("c"),
  ]
RUBY

# YARV: swap and opt_reverse
assert_equal '["x", "Y", "c", "A", "t", "A", "b", "C", "d"]', <<~'RUBY'
  class Swap
    def initialize(s)
      @a, @b, @c, @d = s.split("")
    end

    def swap
      a, b = @a, @b
      b = b.upcase
      @a, @b = a, b
    end

    def reverse_odd
      a, b, c = @a, @b, @c
      b = b.upcase
      @a, @b, @c = a, b, c
    end

    def reverse_even
      a, b, c, d = @a, @b, @c, @d
      a = a.upcase
      c = c.upcase
      @a, @b, @c, @d = a, b, c, d
    end
  end

  Swap.new("xy").swap + Swap.new("cat").reverse_odd + Swap.new("abcd").reverse_even
RUBY

assert_normal_exit %{
  class Bug20997
    def foo(&) = self.class.name(&)

    new.foo
  end
}

# This used to trigger a "try to mark T_NONE"
# due to an uninitialized local in foo.
assert_normal_exit %{
  def foo(...)
    _local_that_should_nil_on_call = GC.start
  end

  def test_bug21021
    puts [], [], [], [], [], []
    foo []
  end

  GC.stress = true
  test_bug21021
}

assert_equal 'nil', %{
  def foo(...)
    _a = _b = _c = binding.local_variable_get(:_c)

    _c
  end

  # [Bug #21021]
  def test_local_fill_in_forwardable
    puts [], [], [], [], []
    foo []
  end

  test_local_fill_in_forwardable.inspect
}
