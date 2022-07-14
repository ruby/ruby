# Run can run this test file directly with:
# make -j miniruby && RUST_BACKTRACE=1 ruby --disable=gems bootstraptest/runner.rb --ruby="./miniruby -I./lib -I. -I.ext/common --disable-gems --yjit-call-threshold=1 --yjit-verify-ctx" bootstraptest/test_yjit_new_backend.rb

assert_equal '1', %q{
    def foo()
      1
    end
    foo()
}

assert_equal '3', %q{
    def foo(n)
      n
    end
    foo(3)
}

assert_equal '14', %q{
    def foo(n)
      n + n
    end
    foo(7)
}

# newarray
assert_equal '[7]', %q{
    def foo(n)
      [n]
    end
    foo(7)
}

# newarray, opt_plus
assert_equal '[8]', %q{
    def foo(n)
      [n+1]
    end
    foo(7)
}

# setlocal, getlocal, opt_plus
assert_equal '10', %q{
    def foo(n)
        m = 3
        n + m
    end
    foo(7)
}

# putstring
assert_equal 'foo', %q{
    def foo(n)
        "foo"
    end
    foo(7)
}

# duphash
assert_equal '{:a=>888}', %q{
    def foo()
        { a: 888 }
    end
    foo()
}

# putobject, getlocal, newhash
assert_equal '{:a=>777}', %q{
    def foo(n)
        { a: n }
    end
    foo(777)
}

# TODO: progress towards getting branches and calls working
=begin
def foo(n)
    if n
        n
    end
end
puts foo(0)
=end
