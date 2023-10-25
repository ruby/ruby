# Simple tests that we know we can pass
# To keep track of what we got working during the Rust port
# And avoid breaking/losing functionality
#
# Say "Thread" here to dodge WASM CI check. We use ractors here
# which WASM doesn't support and it only greps for "Thread".

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

assert_equal '5', %q{
  def plus(a, b)
    a + b
  end

  plus(3, 2)
}

assert_equal '1', %q{
  def foo(a, b)
    a - b
  end

  foo(3, 2)
}

assert_equal 'true', %q{
  def foo(a, b)
    a < b
  end

  foo(2, 3)
}

# Bitwise left shift
assert_equal '4', %q{
  def foo(a, b)
    1 << 2
  end

  foo(1, 2)
}

assert_equal '-7', %q{
  def foo(a, b)
    -7
  end

  foo(1, 2)
}

# Putstring
assert_equal 'foo', %q{
  def foo(a, b)
    "foo"
  end

  foo(1, 2)
}

assert_equal '-6', %q{
  def foo(a, b)
    a + -7
  end

  foo(1, 2)
}

assert_equal 'true', %q{
  def foo(a, b)
    a == b
  end

  foo(3, 3)
}

assert_equal 'true', %q{
  def foo(a, b)
    a < b
  end

  foo(3, 5)
}

assert_equal '777', %q{
  def foo(a)
    if a
      777
    else
      333
    end
  end

  foo(true)
}

assert_equal '5', %q{
  def foo(a, b)
    while a < b
      a += 1
    end
    a
  end

  foo(1, 5)
}

# opt_aref
assert_equal '2', %q{
  def foo(a, b)
    a[b]
  end

  foo([0, 1, 2], 2)
}

# Simple function calls with 0, 1, 2 arguments
assert_equal '-2', %q{
  def bar()
    -2
  end

  def foo(a, b)
    bar()
  end

  foo(3, 2)
}
assert_equal '2', %q{
  def bar(a)
    a
  end

  def foo(a, b)
    bar(b)
  end

  foo(3, 2)
}
assert_equal '1', %q{
  def bar(a, b)
    a - b
  end

  def foo(a, b)
    bar(a, b)
  end

  foo(3, 2)
}

# Regression test for assembler bug
assert_equal '1', %q{
  def check_index(index)
    if 0x40000000 < index
        return -1
    end
    1
  end

  check_index 2
}

# Setivar test
assert_equal '2', %q{
  class Klass
    attr_accessor :a

    def set()
        @a = 2
    end

    def get()
        @a
    end
  end

  o = Klass.new
  o.set()
  o.a
}

# Regression for putobject bug
assert_equal '1.5', %q{
  def foo(x)
    x
  end

  def bar
    foo(1.5)
  end

  bar()
}

# Getivar with an extended ivar table
assert_equal '3', %q{
  class Foo
    def initialize
      @x1 = 1
      @x2 = 1
      @x3 = 1
      @x4 = 3
    end

    def bar
      @x4
    end
  end

  f = Foo.new
  f.bar
}

assert_equal 'true', %q{
  x = [[false, true]]
  for i, j in x
    ;
  end
  j
}

# Regression for getivar
assert_equal '[nil]', %q{
  [TrueClass].each do |klass|
    klass.class_eval("def foo = @foo")
  end

  [true].map do |instance|
    instance.foo
  end
}

# Regression for send
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

# Array access regression test
assert_equal '[0, 1, 2, 3, 4, 5]', %q{
  def expandarray_useless_splat
    arr = [0, 1, 2, 3, 4, 5]
    a, * = arr
  end

  expandarray_useless_splat
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

assert_equal '2', %q{
  def foo(s)
    s.foo
  end

  S = Struct.new(:foo)
  foo(S.new(1))
  foo(S.new(2))
}

# Try to compile new method while OOM
assert_equal 'ok', %q{
  def foo
    :ok
  end

  RubyVM::YJIT.simulate_oom! if defined?(RubyVM::YJIT)

  foo
}

# test hitting a branch stub when out of memory
assert_equal 'ok', %q{
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

# Ractor.current returns a current ractor
assert_equal 'Ractor', %q{
  Ractor.current.class
}

# Ractor.new returns new Ractor
assert_equal 'Ractor', %q{
  Ractor.new{}.class
}

# Ractor.allocate is not supported
assert_equal "[:ok, :ok]", %q{
  rs = []
  begin
    Ractor.allocate
  rescue => e
    rs << :ok if e.message == 'allocator undefined for Ractor'
  end

  begin
    Ractor.new{}.dup
  rescue
    rs << :ok if e.message == 'allocator undefined for Ractor'
  end

  rs
}

# A return value of a Ractor block will be a message from the Ractor.
assert_equal 'ok', %q{
  # join
  r = Ractor.new do
    'ok'
  end
  r.take
}

# Passed arguments to Ractor.new will be a block parameter
# The values are passed with Ractor-communication pass.
assert_equal 'ok', %q{
  # ping-pong with arg
  r = Ractor.new 'ok' do |msg|
    msg
  end
  r.take
}

# Pass multiple arguments to Ractor.new
assert_equal 'ok', %q{
  # ping-pong with two args
  r =  Ractor.new 'ping', 'pong' do |msg, msg2|
    [msg, msg2]
  end
  'ok' if r.take == ['ping', 'pong']
}

# Ractor#send passes an object with copy to a Ractor
# and Ractor.receive in the Ractor block can receive the passed value.
assert_equal 'ok', %q{
  r = Ractor.new do
    msg = Ractor.receive
  end
  r.send 'ok'
  r.take
}

assert_equal '[1, 2, 3]', %q{
  def foo(arr)
    arr << 1
    arr << 2
    arr << 3
    arr
  end

  def bar()
    foo([])
  end

  bar()
}
