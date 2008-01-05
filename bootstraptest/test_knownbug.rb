#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
  class X < RuntimeError;end
  x = [X]
  begin
   raise X
  rescue *x
   :ok
  end
}, '[ruby-core:14537]'

# test is not written...
# * [ruby-dev:31819] rb_clear_cache_by_class
# * [ruby-dev:31820] valgrind set_trace_func
