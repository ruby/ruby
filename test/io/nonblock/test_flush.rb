require 'test/unit'
begin
  require 'io/nonblock'
rescue LoadError
end

class TestIONonblock < Test::Unit::TestCase
  def test_flush                # [ruby-dev:24985]
    r,w = IO.pipe
    w.nonblock = true
    w.sync = false
    w << "b"
    w.flush
    w << "a" * 4096
    Thread.new {
      Thread.pass
      w.close
    }
    result = ""
    t = Thread.new {
      while (Thread.pass; s = r.read(4096))
        result << s
      end
    }
    assert_raise(IOError) {w.flush}
    t.join
    assert_equal("b", result)
  end
end if IO.method_defined?(:nonblock)
