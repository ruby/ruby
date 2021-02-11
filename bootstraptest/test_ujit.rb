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

# Test for GC safety. Don't invalidate dead iseqs.
assert_normal_exit %q{
  Class.new do
    def foo
      itself
    end

    new.foo
    UJIT.install_entry(RubyVM::InstructionSequence.of(instance_method(:foo)))
    new.foo
  end

  4.times { GC.start }
  def itself
    self
  end
}
