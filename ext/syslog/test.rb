#!/usr/bin/env ruby
# $RoughId: test.rb,v 1.8 2001/11/24 18:11:32 knu Exp $
# $Id$

# Please only run this test on machines reasonable for testing.
# If in doubt, ask your admin.

require 'runit/testcase'
require 'runit/cui/testrunner'

# Prepend current directory to load path for testing.
$:.unshift('.')

require 'syslog'

class TestSyslog < RUNIT::TestCase
  def test_s_new
    assert_exception(NameError) {
      Syslog.new
    }
  end

  def test_s_instance
    sl1 = Syslog.instance
    sl2 = Syslog.open
    sl3 = Syslog.instance

    assert_equal(sl1, sl2)
    assert_equal(sl1, sl3)
  ensure
    sl1.close
  end

  def test_s_open
    # default parameters
    sl = Syslog.open

    assert_equal($0, sl.ident)
    assert_equal(Syslog::LOG_PID | Syslog::LOG_CONS, sl.options)
    assert_equal(Syslog::LOG_USER, sl.facility)

    # open without close
    assert_exception(RuntimeError) {
      sl.open
    }

    sl.close

    # given parameters
    sl = Syslog.open("foo", Syslog::LOG_NDELAY | Syslog::LOG_PERROR, Syslog::LOG_DAEMON) 

    assert_equal('foo', sl.ident)
    assert_equal(Syslog::LOG_NDELAY | Syslog::LOG_PERROR, sl.options)
    assert_equal(Syslog::LOG_DAEMON, sl.facility)

    sl.close

    # default parameters again (after close)
    sl = Syslog.open
    sl.close

    assert_equal($0, sl.ident)
    assert_equal(Syslog::LOG_PID | Syslog::LOG_CONS, sl.options)
    assert_equal(Syslog::LOG_USER, sl.facility)

    # block
    param = nil
    Syslog.open { |param| }
    assert_equal(sl, param)
  ensure
    sl.close
  end

  def test_opened?
    sl = Syslog.instance
    assert_equal(false, sl.opened?)

    sl.open
    assert_equal(true, sl.opened?)

    sl.close
    assert_equal(false, sl.opened?)

    sl.open {
      assert_equal(true, sl.opened?)
    }

    assert_equal(false, sl.opened?)
  end

  def test_mask
    sl = Syslog.open

    orig = sl.mask

    sl.mask = Syslog.LOG_UPTO(Syslog::LOG_ERR)
    assert_equal(Syslog.LOG_UPTO(Syslog::LOG_ERR), sl.mask)

    sl.mask = Syslog.LOG_MASK(Syslog::LOG_CRIT)
    assert_equal(Syslog.LOG_MASK(Syslog::LOG_CRIT), sl.mask)

    sl.mask = orig
  ensure
    sl.close
  end

  def test_log
    stderr = IO::pipe

    pid = fork {
      stderr[0].close
      STDERR.reopen(stderr[1])
      stderr[1].close

      options = Syslog::LOG_PERROR | Syslog::LOG_NDELAY

      Syslog.open("syslog_test", options) { |sl|
	sl.log(Syslog::LOG_NOTICE, "test1 - hello, %s!", "world")
	sl.notice("test1 - hello, %s!", "world")
      }

      Syslog.open("syslog_test", options | Syslog::LOG_PID) { |sl|
	sl.log(Syslog::LOG_CRIT, "test2 - pid")
	sl.crit("test2 - pid")
      }
      exit!
    }

    stderr[1].close
    Process.waitpid(pid)

    # LOG_PERROR is not yet implemented on Cygwin.
    return if RUBY_PLATFORM =~ /cygwin/

    2.times {
      assert_equal("syslog_test: test1 - hello, world!\n", stderr[0].gets)
    }

    2.times {
      assert_equal(format("syslog_test[%d]: test2 - pid\n", pid), stderr[0].gets)
    }
  end

  def test_inspect
    Syslog.open { |sl|
      assert_equal(format('<#%s: opened=%s, ident="%s", ' +
			  'options=%d, facility=%d, mask=%d>',
			  Syslog, sl.opened?, sl.ident,
			  sl.options, sl.facility, sl.mask),
		   sl.inspect)
    }
  end
end

if $0 == __FILE__
  suite = RUNIT::TestSuite.new

  suite.add_test(TestSyslog.suite)

  RUNIT::CUI::TestRunner.run(suite)
end
