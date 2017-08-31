# frozen_string_literal: false
require 'test/unit'

class TestWaitForSingleFD < Test::Unit::TestCase
  require '-test-/wait_for_single_fd'

  def with_pipe
    r, w = IO.pipe
    begin
      yield r, w
    ensure
      r.close unless r.closed?
      w.close unless w.closed?
    end
  end

  def test_wait_for_valid_fd
    with_pipe do |r,w|
      rc = IO.wait_for_single_fd(w.fileno, RB_WAITFD_OUT, nil)
      assert_equal RB_WAITFD_OUT, rc
    end
  end

  def test_wait_for_invalid_fd
    # Negative FDs should not cause NoMemoryError or segfault when
    # using select().  For now, match the poll() implementation
    # used on Linux, which sleeps the given amount of time given
    # when fd is negative (as documented in the Linux poll(2) manpage)
    assert_equal 0, IO.wait_for_single_fd(-999, RB_WAITFD_IN, 0)
    assert_equal 0, IO.wait_for_single_fd(-1, RB_WAITFD_OUT, 0)

    # FreeBSD 8.2 or prior sticks this
    # http://bugs.ruby-lang.org/issues/5524
    skip if /freebsd[1-8]/ =~ RUBY_PLATFORM
    with_pipe do |r,w|
      wfd = w.fileno
      w.close
      assert_raise(Errno::EBADF) do
        IO.wait_for_single_fd(wfd, RB_WAITFD_OUT, nil)
      end
    end
  end

  def test_wait_for_closed_pipe
    with_pipe do |r,w|
      w.close
      rc = IO.wait_for_single_fd(r.fileno, RB_WAITFD_IN, nil)
      assert_equal RB_WAITFD_IN, rc
    end
  end


end
