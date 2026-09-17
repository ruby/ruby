# frozen_string_literal: true
require 'test/unit'
require 'io/wait'
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

  def test_io_close_across_fibers
    # omit "Interrupting a io_wait read is not supported!" if RUBY_PLATFORM =~ /mswin|mingw/

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

  def test_io_close_interrupt_does_not_escape_blocking_operation
    with_socket_pair do |source, source_peer|
      with_socket_pair do |unrelated, unrelated_peer|
        errors = []

        thread = Thread.new do
          scheduler = Scheduler.new
          Fiber.set_scheduler scheduler

          5.times do
            Fiber.schedule do
              begin
                source.wait_readable(0.01)
                source.close
              rescue => error
                errors << [:source, error]
              end

              begin
                unrelated.wait_readable(0.01)
              rescue => error
                errors << [:unrelated, error]
              end
            end
          end
        end

        thread.join

        assert_equal 4, errors.size
        assert_equal [:source], errors.map(&:first).uniq
        errors.each do |location, error|
          assert_equal :source, location
          assert_instance_of IOError, error
          assert_match(/closed/, error.message)
        end
      end
    end
  end

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

  def test_io_close_blocking_fiber
    # omit "Interrupting a io_wait read is not supported!" if RUBY_PLATFORM =~ /mswin|mingw/

    with_socket_pair do |i, o|
      error = nil
      scheduler = nil

      scheduler_class = Class.new(Scheduler) do
        attr_reader :interrupt_target

        def fiber_interrupt(target, exception)
          @interrupt_target = target
          super
        end
      end

      thread = Thread.new do
        scheduler = scheduler_class.new
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

      interrupt_target = scheduler.interrupt_target
      assert_not_predicate interrupt_target, :alive?
      assert_nil interrupt_target.transfer
      assert_nil interrupt_target.raise(IOError.new)
    end
  end
end
