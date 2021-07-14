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

  GC.verify_compaction_references(double_heap: true, toward: :empty)

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
