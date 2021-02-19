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
