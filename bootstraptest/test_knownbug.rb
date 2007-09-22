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
    begin
      remove_method :display
    rescue NameError
    end
  end
  :ok
}, '[ruby-dev:31816]'

assert_equal 'ok', %q{
  class B
    def m() :fail end
  end
  class C < B
    undef m
    begin
      remove_method :m
    rescue NameError
    end
  end
  begin
    C.new.m
  rescue NameError
    :ok
  end
}, '[ruby-dev:31817]'

assert_equal 'ok', %q{
  Process.setrlimit(Process::RLIMIT_STACK, 1024*1024)
  class C
    attr "a" * (2*1024*1024)
  end
  :ok
}, '[ruby-dev:31818]'

