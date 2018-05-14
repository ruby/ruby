# frozen_string_literal: false
require 'test/unit'

class TestWaitForSingleFD < Test::Unit::TestCase
  require '-test-/wait_for_single_fd'

  def test_wait_for_valid_fd
    IO.pipe do |r,w|
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
    if /freebsd([\d\.]+)/ =~ RUBY_PLATFORM
      ver = $1.to_r
      skip 'FreeBSD <= 8.2' if ver <= 8.2r
    end
    IO.pipe do |r,w|
      wfd = w.fileno
      w.close
      assert_raise(Errno::EBADF) do
        IO.wait_for_single_fd(wfd, RB_WAITFD_OUT, nil)
      end
    end
  end

  def test_wait_for_closed_pipe
    IO.pipe do |r,w|
      w.close
      rc = IO.wait_for_single_fd(r.fileno, RB_WAITFD_IN, nil)
      assert_equal RB_WAITFD_IN, rc
    end
  end

  def test_wait_for_kqueue
    skip 'no kqueue' unless IO.respond_to?(:kqueue_test_wait)
    assert_equal RB_WAITFD_IN, IO.kqueue_test_wait
  end
end
