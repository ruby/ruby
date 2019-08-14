# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'
require 'timeout'
require 'socket'
begin
  require 'io/wait'
rescue LoadError
end

class TestIOWait < Test::Unit::TestCase

  def setup
    if /mswin|mingw/ =~ RUBY_PLATFORM
      @r, @w = Socket.pair(Socket::AF_INET, Socket::SOCK_STREAM, 0)
    else
      @r, @w = IO.pipe
    end
  end

  def teardown
    @r.close unless @r.closed?
    @w.close unless @w.closed?
  end

  def test_nread
    assert_equal 0, @r.nread
    @w.syswrite "."
    sleep 0.1
    assert_equal 1, @r.nread
  end

  def test_nread_buffered
    @w.syswrite ".\n!"
    assert_equal ".\n", @r.gets
    assert_equal 1, @r.nread
  end

  def test_ready?
    assert_not_predicate @r, :ready?, "shouldn't ready, but ready"
    @w.syswrite "."
    sleep 0.1
    assert_predicate @r, :ready?, "should ready, but not"
  end

  def test_buffered_ready?
    @w.syswrite ".\n!"
    assert_equal ".\n", @r.gets
    assert_predicate @r, :ready?
  end

  def test_wait
    assert_nil @r.wait(0)
    @w.syswrite "."
    sleep 0.1
    assert_equal @r, @r.wait(0)
  end

  def test_wait_buffered
    @w.syswrite ".\n!"
    assert_equal ".\n", @r.gets
    assert_equal true, @r.wait(0)
  end

  def test_wait_forever
    th = Thread.new { sleep 0.01; @w.syswrite "." }
    assert_equal @r, @r.wait
  ensure
    th.join
  end

  def test_wait_eof
    th = Thread.new { sleep 0.01; @w.close }
    ret = nil
    assert_nothing_raised(Timeout::Error) do
      Timeout.timeout(0.1) { ret = @r.wait }
    end
    assert_equal @r, ret
  ensure
    th.join
  end

  def test_wait_readable
    assert_nil @r.wait_readable(0)
    @w.syswrite "."
    IO.select([@r])
    assert_equal @r, @r.wait_readable(0)
  end

  def test_wait_readable_buffered
    @w.syswrite ".\n!"
    assert_equal ".\n", @r.gets
    assert_equal true, @r.wait_readable(0)
  end

  def test_wait_readable_forever
    th = Thread.new { sleep 0.01; @w.syswrite "." }
    assert_equal @r, @r.wait_readable
  ensure
    th.join
  end

  def test_wait_readable_eof
    th = Thread.new { sleep 0.01; @w.close }
    ret = nil
    assert_nothing_raised(Timeout::Error) do
      Timeout.timeout(0.1) { ret = @r.wait_readable }
    end
    assert_equal @r, ret
  ensure
    th.join
  end

  def test_wait_writable
    assert_equal @w, @w.wait_writable
  end

  def test_wait_writable_timeout
    assert_equal @w, @w.wait_writable(0.01)
    written = fill_pipe
    assert_nil @w.wait_writable(0.01)
    @r.read(written)
    assert_equal @w, @w.wait_writable(0.01)
  end

  def test_wait_writable_EPIPE
    fill_pipe
    @r.close
    assert_equal @w, @w.wait_writable
  end

  def test_wait_writable_closed
    @w.close
    assert_raise(IOError) { @w.wait_writable }
  end

  def test_wait_readwrite
    assert_equal @r.wait(0, :write), @r.wait(0, :read_write)
  end

  def test_wait_readwrite_timeout
    assert_equal @w, @w.wait(0.01, :read_write)
    written = fill_pipe
    if /aix/ =~ RUBY_PLATFORM
      # IO#wait internally uses select(2) on AIX.
      # AIX's select(2) returns "readable" for the write-side fd
      # of a pipe, so @w.wait(0.01, :read_write) does not return nil.
      assert_equal @w, @w.wait(0.01, :read_write)
    else
      assert_nil @w.wait(0.01, :read_write)
    end
    @r.read(written)
    assert_equal @w, @w.wait(0.01, :read_write)
  end

private

  def fill_pipe
    written = 0
    buf = " " * 4096
    begin
      written += @w.write_nonblock(buf)
    rescue Errno::EAGAIN, Errno::EWOULDBLOCK
      return written
    end while true
  end
end if IO.method_defined?(:wait)
