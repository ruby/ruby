# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberIO < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair

    unless i.nonblock? && o.nonblock?
      i.close
      o.close
      skip "I/O is not non-blocking!"
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
    skip unless defined?(UNIXSocket)

    16.times.map do
      Thread.new do
        i, o = UNIXSocket.pair

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
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair

    unless i.nonblock? && o.nonblock?
      i.close
      o.close
      skip "I/O is not non-blocking!"
    end

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
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    i.nonblock = false
    o.nonblock = false

    message = nil

    thread = Thread.new do
      # This scheduler provides non-blocking `io_read`/`io_write`:
      scheduler = IOBufferScheduler.new
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
end
