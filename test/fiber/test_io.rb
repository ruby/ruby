# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberIO < Test::Unit::TestCase
  MESSAGE = "Hello World"

  private def read_test_on_io(i,o, read_size: 20)
    message = nil

    thread = Thread.new do
      scheduler = Scheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        message = i.read(read_size)
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

  def test_read_io_pipe
    read_test_on_io(*IO.pipe)
  end

  def test_read_unixsocket
    omit unless defined?(UNIXSocket)
    read_test_on_io(*UNIXSocket.pair)
  end

  def test_read_tcp
    server = TCPServer.new('localhost', 0)
    i = TCPSocket.new('localhost', server.local_address.ip_port)
    o = server.accept
    server.close
    read_test_on_io(i,o)
  end

  def test_read_udp
    omit "nonblocking UDP isn't supported on Windows" if RUBY_PLATFORM=~/mswin|mingw/
    i = Addrinfo.udp("localhost", 0).bind
    o = i.connect_address.connect
    read_test_on_io(i,o, read_size: MESSAGE.bytesize)
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
    omit "Windows has a different closing behaviour with nonblock=true" if RUBY_PLATFORM=~/mswin|mingw/
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
end
