# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

require 'timeout'

class TestFiberIOBuffer < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read_write_blocking
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    i.nonblock = false
    o.nonblock = false

    message = nil

    thread = Thread.new do
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        message = i.read(20)
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
  ensure
    i&.close
    o&.close
  end

  def test_timeout_after
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    i.nonblock = false
    o.nonblock = false

    message = nil
    error = nil

    thread = Thread.new do
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        Timeout.timeout(0.1) do
          message = i.read(20)
        end
      rescue Timeout::Error => error
        # Assertions below.
      ensure
        i.close
      end
    end

    thread.join

    assert_nil message
    assert_kind_of Timeout::Error, error
  ensure
    i&.close
    o&.close
  end

  def test_read_nonblock
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair

    message = nil

    thread = Thread.new do
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        message = i.read_nonblock(20, exception: false)
        i.close
      end
    end

    thread.join

    assert_equal :wait_readable, message
  ensure
    i&.close
    o&.close
  end

  def test_write_nonblock
    skip "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair

    thread = Thread.new do
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        o.write_nonblock(MESSAGE, exception: false)
        o.close
      end
    end

    thread.join

    assert_equal MESSAGE, i.read
  ensure
    i&.close
    o&.close
  end
end
