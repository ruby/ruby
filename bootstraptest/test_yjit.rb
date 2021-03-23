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
