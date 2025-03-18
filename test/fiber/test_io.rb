# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberIO < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read
    omit unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    if RUBY_PLATFORM=~/mswin|mingw/
      i.nonblock = true
      o.nonblock = true
    end

    message = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        message = i.read(20)
        i.close
      end

      Fiber.schedule do
        o.write("Hello World")
        o.close
      end
    end

    thread.join

    assert_equal MESSAGE, message
    assert_predicate(i, :closed?)
    assert_predicate(o, :closed?)
  end

  def test_heavy_read
    omit unless defined?(UNIXSocket)

    16.times.map do
      Thread.new do
        i, o = UNIXSocket.pair
        if RUBY_PLATFORM=~/mswin|mingw/
          i.nonblock = true
          o.nonblock = true
        end

        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        Fiber.schedule do
          i.read(20)
          i.close
        end

        Fiber.schedule do
          o.write("Hello World")
          o.close
        end
      end
    end.each(&:join)
  end

  def test_epipe_on_read
    omit unless defined?(UNIXSocket)
    omit "nonblock=true isn't properly supported on Windows" if RUBY_PLATFORM=~/mswin|mingw/

    i, o = UNIXSocket.pair

    error = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        begin
          i.close
          o.write(MESSAGE)
        rescue => error
          # Saved into error.
        end
      end
    end

    thread.join

    i.close
    o.close

    assert_kind_of Errno::EPIPE, error
  end

  def test_tcp_accept
    server = TCPServer.new('localhost', 0)

    th = Thread.new do
      Fiber.set_scheduler(Scheduler.new)

      Fiber.schedule do
        sender = server.accept
        sender.wait_writable
        sender.write "hello"
        sender.close
      end
    end

    recver = TCPSocket.new('localhost', server.local_address.ip_port)
    assert "hello", recver.read

    recver.close
    server.close
    th.join
  end

  def test_tcp_connect
    server = TCPServer.new('localhost', 0)

    th = Thread.new do
      Fiber.set_scheduler(Scheduler.new)

      Fiber.schedule do
        sender = TCPSocket.new('localhost', server.local_address.ip_port)
        sender.write "hello"
        sender.close
      end
    end

    recver = server.accept
    assert "hello", recver.read

    recver.close
    server.close
    th.join
  end

  def test_read_write_blocking
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    i.nonblock = false
    o.nonblock = false

    message = nil

    thread = Thread.new do
      # This scheduler provides non-blocking `io_read`/`io_write`:
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        # We add 1 here, to force the read to block (testing that specific code path).
        message = i.read(MESSAGE.bytesize + 1)
        i.close
      end

      Fiber.schedule do
        o.write(MESSAGE)
        o.close
      end
    end

    thread.join

    assert_equal MESSAGE, message
    assert_predicate(i, :closed?)
    assert_predicate(o, :closed?)
  end

  def test_puts_empty
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    i.nonblock = false
    o.nonblock = false

    thread = Thread.new do
      # This scheduler provides non-blocking `io_read`/`io_write`:
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        # This was causing a segfault on older Ruby.
        o.puts ""
        o.puts nil
        o.close
      end
    end

    thread.join

    message = i.read
    i.close

    assert_equal $/*2, message
  end

  def test_io_select
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    UNIXSocket.pair do |r, w|
      result = nil

      thread = Thread.new do
        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        Fiber.schedule do
          w.write("Hello World")
          result = IO.select([r], [w])
        end
      end

      thread.join

      assert_equal [[r], [w], []], result
    end
  end

  def test_backquote
    result = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler
      Fiber.schedule do
        result = `#{EnvUtil.rubybin} -e "sleep 0.1;puts %[ok]"`
      end
    end
    thread.join

    assert_equal "ok\n", result
  end

  # Tests for https://bugs.ruby-lang.org/issues/20723 which would
  # otherwise deadlock this test.
  def test_close_while_reading_on_thread
    # Windows has UNIXSocket, but only with VS 2019+
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = Socket.pair(:UNIX, :STREAM)
    if RUBY_PLATFORM=~/mswin|mingw/
      i.nonblock = true
      o.nonblock = true
    end

    reading_thread = Thread.new do
      Thread.current.report_on_exception = false
      i.wait_readable
    end

    fs_thread = Thread.new do
      # Wait until the reading thread is blocked on read:
      Thread.pass until reading_thread.status == "sleep"

      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler
      Fiber.schedule do
        i.close
      end
    end

    assert_raise(IOError) { reading_thread.join }
    refute_nil fs_thread.join(5), "expected thread to terminate within 5 seconds"

    assert_predicate(i, :closed?)
  ensure
    fs_thread&.kill
    fs_thread&.join rescue nil
    reading_thread&.kill
    reading_thread&.join rescue nil
    i&.close
    o&.close
  end
end
