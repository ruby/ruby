#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

# test is not written...
flunk '[ruby-dev:31819] rb_clear_cache_by_class'
flunk '[ruby-dev:31820] valgrind set_trace_func'

assert_equal 'ok', %q{
  class X < RuntimeError;end
  x = [X]
  begin
   raise X
  rescue *x
   :ok
  end
}, '[ruby-core:14537]'

assert_equal 'ok', %q{
  while true
    *, z = 1
    break
  end
  :ok
}, '[ruby-dev:32892]'


assert_equal 'ok', %q{
  1.times do
    [
      1, 2, 3, 4, 5, 6, 7, 8,
      begin
        false ? next : p
        break while true
      end
    ]
  end
  :ok
}, '[ruby-dev:32882]'


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

assert_equal 'true', %{
  t = Thread.new { loop {} }
  pid = fork {
      exit t.status != "run"
  }
  Process.wait pid
  $?.success?
}

assert_valid_syntax('1.times {|i|print (42),1;}', '[ruby-list:44479]')
