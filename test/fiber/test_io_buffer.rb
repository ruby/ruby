# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

require 'timeout'

class TestFiberIOBuffer < Test::Unit::TestCase
  MESSAGE = "Hello World"

  def test_read_write_blocking
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    i.nonblock = false
    o.nonblock = false

    message = nil

    thread = Thread.new do
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
  ensure
    i&.close
    o&.close
  end

  def test_timeout_after
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

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
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

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
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

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

  def test_io_buffer_read_write
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    source_buffer = IO::Buffer.for("Hello World!")
    destination_buffer = IO::Buffer.new(source_buffer.size)

    # Test non-scheduler code path:
    source_buffer.write(o, source_buffer.size)
    destination_buffer.read(i, source_buffer.size)
    assert_equal source_buffer, destination_buffer

    # Test scheduler code path:
    destination_buffer.clear

    thread = Thread.new do
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        source_buffer.write(o, source_buffer.size)
        destination_buffer.read(i, source_buffer.size)
      end
    end

    thread.join

    assert_equal source_buffer, destination_buffer
  ensure
    i&.close
    o&.close
  end

  def nonblockable?(io)
    io.nonblock{}
    true
  rescue
    false
  end

  def test_io_buffer_pread_pwrite
    file = Tempfile.new("test_io_buffer_pread_pwrite")

    omit "Non-blocking file IO is not supported" unless nonblockable?(file)

    source_buffer = IO::Buffer.for("Hello World!")
    destination_buffer = IO::Buffer.new(source_buffer.size)

    # Test non-scheduler code path:
    source_buffer.pwrite(file, 1, source_buffer.size)
    destination_buffer.pread(file, 1, source_buffer.size)
    assert_equal source_buffer, destination_buffer

    # Test scheduler code path:
    destination_buffer.clear
    file.truncate(0)

    thread = Thread.new do
      scheduler = IOBufferScheduler.new
      Fiber.set_scheduler scheduler

      Fiber.schedule do
        source_buffer.pwrite(file, 1, source_buffer.size)
        destination_buffer.pread(file, 1, source_buffer.size)
      end
    end

    thread.join

    assert_equal source_buffer, destination_buffer
  ensure
    file&.close!
  end
end
