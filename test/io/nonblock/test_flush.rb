require 'test/unit'
require 'io/nonblock'

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
    Thread.new {
      Thread.pass
      nil while r.read(4096)
    }
    assert_raise(IOError) {w.flush}
  end
end
