begin
  require 'io/console'
  require 'pty'
  require 'test/unit'
rescue LoadError
end

class TestIO_Console < Test::Unit::TestCase
  def test_raw
    helper {|m, s|
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
    helper {|m, s|
      assert(s.echo?)
      m.print "a"
      assert_equal("a", m.readpartial(10))
    }
  end

  def test_noecho
    helper {|m, s|
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
    helper {|m, s|
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
    helper {|m, s|
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
    helper {|m, s|
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
    helper {|m, s|
      m.print "a"
      s.iflush
      m.print "b\n"
      assert_equal("b\n", s.readpartial(10))
    }
  end

  def test_oflush
    helper {|m, s|
      s.print "a"
      s.oflush # oflush may be issued after "a" is already sent.
      s.print "b"
      assert_include(["b", "ab"], m.readpartial(10))
    }
  end

  def test_ioflush
    helper {|m, s|
      m.print "a"
      s.ioflush
      m.print "b\n"
      assert_equal("b\n", s.readpartial(10))
    }
  end

  def test_ioflush2
    helper {|m, s|
      s.print "a"
      s.ioflush # ioflush may be issued after "a" is already sent.
      s.print "b"
      assert_include(["b", "ab"], m.readpartial(10))
    }
  end

  def test_winsize
    helper {|m, s|
      begin
        assert_equal([0, 0], s.winsize)
      rescue Errno::EINVAL # OpenSolaris 2009.06 TIOCGWINSZ causes Errno::EINVAL before TIOCSWINSZ.
      end
    }
  end

  private
  def helper
    m, s = PTY.open
  rescue RuntimeError
    skip $!
  else
    yield m, s
  ensure
    m.close if m
    s.close if s
  end
end if defined?(PTY) and defined?(IO::console)
