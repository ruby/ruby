#
# This test file concludes tests which point out known bugs.
# So all tests will cause failure.
#

assert_equal 'ok', %q{
begin
  r, w = IO.pipe
  w.write "foo"
  w.close
  # assert_raise(IOError, "[ruby-dev:31650]") { 20000.times { r.ungetc "a" } }
  r.getc
  20000.times { r.ungetc "a" }
  data = r.read
  if data.size == 20002 && data[-5..-1] == "aaaoo"
    :ok
  end
ensure
  r.close
end
}, 'rename test/ruby/test_io.rb#_test_ungetc if fixed'

