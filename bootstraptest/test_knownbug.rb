#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  class C
    define_method(:foo) {
      if block_given?
        :ok
      else
        :ng
      end
    }
  end
  C.new.foo {}
}, '[ruby-core:14813]'

assert_equal 'ok', %q{
  class C
    define_method(:foo) {
      if block_given?
        :ng
      else
        :ok
      end
    }
  end
  C.new.foo
}, '[ruby-core:14813]'

# test is not written...
flunk '[ruby-dev:31819] rb_clear_cache_by_class'
flunk '[ruby-dev:31820] valgrind set_trace_func'
flunk '[ruby-dev:32746] Invalid read of size 1'

assert_equal 'ok', %q{
  class X < RuntimeError;end
  x = [X]
  begin
   raise X
  rescue *x
   :ok
  end
}, '[ruby-core:14537]'

assert_valid_syntax('1.times {|i|print (42),1;}', '[ruby-list:44479]')

assert_normal_exit %q{
  File.read("empty", nil, nil, {})
}, '[ruby-dev:33072]'

assert_normal_exit %q{
  "abc".gsub(/./, "a" => "z")
}
assert_normal_exit %q{
  Encoding.compatible?("",0)
}
