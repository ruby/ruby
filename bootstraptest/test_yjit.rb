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
  # regression test for a leak caught by an asert on --yjit-call-threshold=2
  Foo = 1

  eval("def foo = [#{(['Foo,']*256).join}]")

  foo
  foo

  Object.send(:remove_const, :Foo)
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
  def bar
    "good"
  end

  def foo
    bar
  end

  foo
  foo

  begin
    GC.verify_compaction_references(double_heap: true, toward: :empty)
  rescue NotImplementedError
    # in case compaction isn't supported
  end

  foo
}

# Test polymorphic getinstancevariable. T_OBJECT -> T_STRING
assert_equal 'ok', %q{
  @hello = @h1 = @h2 = @h3 = @h4 = 'ok'
  str = ""
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
assert_equal '{:foo=>:bar}', %q{
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

assert_equal '[1, 2, nil]', %q{
  def expandarray_rhs_too_small
    a, b, c = [1, 2]
    [a, b, c]
  end

  expandarray_rhs_too_small
  expandarray_rhs_too_small
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
assert_equal '{:foo=>123}', %q{
  def foo
    {foo: 123}
  end

  foo
  foo
}

# newhash
assert_equal '{:foo=>2}', %q{
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

  test
  test

  RubyVM::YJIT.simulate_oom! if defined?(RubyVM::YJIT)

  def foo
    :new
  end

  test
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
