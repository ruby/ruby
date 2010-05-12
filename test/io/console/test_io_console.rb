require 'io/console'
require 'pty'
require 'test/unit'

class TestIO_Console < Test::Unit::TestCase
  def test_raw
    PTY.open {|m, s|
      s.print "abc\n"
      assert_equal("abc\r\n", m.gets)
      s.raw {
        s.print "def\n"
        assert_equal("def\n", m.gets)
      }
      s.print "ghi\n"
      assert_equal("ghi\r\n", m.gets)
    }
  end

  def test_noecho
    PTY.open {|m, s|
      assert(s.echo?)
      m.print "a\n"
      s.print "b\n"
      assert_equal("a\r\nb\r\n", m.readpartial(10))
      assert_equal("a\n", s.readpartial(10))
      s.noecho {
        assert(!s.echo?)
        m.print "a\n"
        s.print "b\n"
        assert_equal("b\r\n", m.readpartial(10))
        assert_equal("a\n", s.readpartial(10))
      }
      assert(s.echo?)
      m.print "a\n"
      s.print "b\n"
      assert_equal("a\r\nb\r\n", m.readpartial(10))
      assert_equal("a\n", s.readpartial(10))
    }
  end

  def test_setecho
    PTY.open {|m, s|
      assert(s.echo?)
      m.print "a\n"
      s.print "b\n"
      assert_equal("a\r\nb\r\n", m.readpartial(10))
      assert_equal("a\n", s.readpartial(10))
      s.echo = false
      assert(!s.echo?)
      m.print "a\n"
      s.print "b\n"
      assert_equal("b\r\n", m.readpartial(10))
      assert_equal("a\n", s.readpartial(10))
      s.echo = true
      assert(s.echo?)
      m.print "a\n"
      s.print "b\n"
      assert_equal("a\r\nb\r\n", m.readpartial(10))
      assert_equal("a\n", s.readpartial(10))
    }
  end

  def test_iflush
    PTY.open {|m, s|
      m.print "a\n"
      s.iflush
      m.print "b\n"
      assert_equal("a\r\nb\r\n", m.readpartial(10))
      assert_equal("b\n", s.readpartial(10))
    }
  end

end
