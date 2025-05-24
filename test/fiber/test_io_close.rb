# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberIOClose < Test::Unit::TestCase
  def with_socket_pair(&block)
    omit "UNIXSocket is not defined!" unless defined?(UNIXSocket)

    UNIXSocket.pair do |i, o|
      if RUBY_PLATFORM =~ /mswin|mingw/
        i.nonblock = true
        o.nonblock = true
      end

      yield i, o
    end
  end

  # Problematic on Windows.
  def test_io_close_across_fibers
    omit "Interrupting a io_wait read is not supported!" if RUBY_PLATFORM =~ /mswin|mingw/

    with_socket_pair do |i, o|
      error = nil

      thread = Thread.new do
        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        Fiber.schedule do
          i.read
        rescue => error
          # Ignore.
        end

        Fiber.schedule do
          i.close
        end
      end

      thread.join

      assert_instance_of IOError, error
      assert_match(/closed/, error.message)
    end
  end

  # Okay on all platforms.
  def test_io_close_blocking_thread
    omit "Interrupting a io_wait read is not supported!" if RUBY_PLATFORM =~ /mswin|mingw/

    with_socket_pair do |i, o|
      error = nil

      reading_thread = Thread.new do
        i.read
      rescue => error
        # Ignore.
      end

      Thread.pass until reading_thread.status == 'sleep'

      thread = Thread.new do
        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        Fiber.schedule do
          i.close
        end
      end

      thread.join
      reading_thread.join

      assert_instance_of IOError, error
      assert_match(/closed/, error.message)
    end
  end

  # Problematic on Windows.
  def test_io_close_blocking_fiber
    omit "Interrupting a io_wait read is not supported!" if RUBY_PLATFORM =~ /mswin|mingw/

    with_socket_pair do |i, o|
      error = nil

      thread = Thread.new do
        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler

        Fiber.schedule do
          begin
            i.read
          rescue => error
            # Ignore.
          end
        end
      end

      Thread.pass until thread.status == 'sleep'

      i.close

      thread.join

      assert_instance_of IOError, error
      assert_match(/closed/, error.message)
    end
  end
end
