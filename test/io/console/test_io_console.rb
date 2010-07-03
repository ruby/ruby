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

  def test_echo
    PTY.open {|m, s|
      assert(s.echo?)
      m.print "a"
      assert_equal("a", m.readpartial(10))
    }
  end

  def test_noecho
    PTY.open {|m, s|
      s.noecho {
	assert(!s.echo?)
	m.print "a"
	sleep 0.1
      }
      m.print "b"
      assert_equal("b", m.readpartial(10))
    }
  end

  def test_noecho2
    PTY.open {|m, s|
      assert(s.echo?)
      m.print "a\n"
      sleep 0.1
      s.print "b\n"
      sleep 0.1
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
      sleep 0.1
      s.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", m.readpartial(10))
      assert_equal("a\n", s.readpartial(10))
    }
  end

  def test_setecho
    PTY.open {|m, s|
      assert(s.echo?)
      s.echo = false
      m.print "a"
      sleep 0.1
      s.echo = true
      m.print "b"
      assert_equal("b", m.readpartial(10))
    }
  end

  def test_setecho2
    PTY.open {|m, s|
      assert(s.echo?)
      m.print "a\n"
      sleep 0.1
      s.print "b\n"
      sleep 0.1
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
      sleep 0.1
      s.print "b\n"
      sleep 0.1
      assert_equal("a\r\nb\r\n", m.readpartial(10))
      assert_equal("a\n", s.readpartial(10))
    }
  end

  def test_iflush
    PTY.open {|m, s|
      m.print "a"
      s.iflush
      m.print "b\n"
      assert_equal("b\n", s.readpartial(10))
    }
  end

  def test_oflush
    PTY.open {|m, s|
      s.print "a"
      s.oflush # oflush may be issued after "a" is already sent.
      s.print "b"
      assert_includes(["b", "ab"], m.readpartial(10))
    }
  end

  def test_ioflush
    PTY.open {|m, s|
      m.print "a"
      s.ioflush
      m.print "b\n"
      assert_equal("b\n", s.readpartial(10))
    }
  end

  def test_ioflush2
    PTY.open {|m, s|
      s.print "a"
      s.ioflush # ioflush may be issued after "a" is already sent.
      s.print "b"
      assert_includes(["b", "ab"], m.readpartial(10))
    }
  end

  def test_winsize
    PTY.open {|m, s|
      assert_equal([0, 0], s.winsize)
    }
  end
end
