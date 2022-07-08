# Run can run this test file directly with:
# make -j miniruby && RUST_BACKTRACE=1 ruby --disable=gems bootstraptest/runner.rb --ruby="./miniruby -I./lib -I. -I.ext/common --disable-gems --yjit-call-threshold=1 --yjit-verify-ctx" bootstraptest/test_yjit_new_backend.rb

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

assert_equal '[7]', %q{
    def foo(n)
      [n]
    end
    foo(7)
}

assert_equal '[8]', %q{
    def foo(n)
      [n+1]
    end
    foo(7)
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
