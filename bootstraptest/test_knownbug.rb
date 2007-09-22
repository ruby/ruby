#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
begin
  r, w = IO.pipe
  w.close
  # assert_raise(IOError, "[ruby-dev:31650]") { 20000.times { r.ungetc "a" } }
  20000.times { r.ungetc "a" }
rescue IOError
  :ok
ensure
  r.close
end
}, 'rename test/ruby/test_io.rb#_test_ungetc if fixed'

assert_equal 'ok', %q{
  class C
    undef display
    remove_method :display
  end
  :ok
}, '[ruby-dev:31816]'

