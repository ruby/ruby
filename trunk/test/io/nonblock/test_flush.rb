require 'test/unit'
require 'timeout'
begin
  require 'io/nonblock'
rescue LoadError
end

class TestIONonblock < Test::Unit::TestCase
  def test_flush
    r,w = IO.pipe
    w.nonblock = true
    w.sync = false
    w << "b"
    w.flush
    w << "a" * 4096
    result = ""
    timeout(10) {
      Thread.new {
        Thread.pass
        w.close
      }
      t = Thread.new {
        while (Thread.pass; s = r.read(4096))
          result << s
        end
      }
      begin
        w.flush # assert_raise(IOError, "[ruby-dev:24985]") {w.flush}
      rescue Errno::EBADF, IOError
        # ignore [ruby-dev:35638]
      end
      assert_nothing_raised {t.join}
    }
    assert_equal(4097, result.size)
  end
end if IO.method_defined?(:nonblock)
