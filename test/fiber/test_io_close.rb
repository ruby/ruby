# frozen_string_literal: true
require 'test/unit'
require 'envutil'
require_relative 'scheduler'

class TestFiberIOClose < Test::Unit::TestCase
  def test_scheduler_unblock_io_close_race
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 10)
    begin;
      class Scheduler
        def initialize(fiber = Fiber.current)
          @fiber = fiber
          @input, @output = IO.pipe
          @ready = Queue.new
          @blocking = 0
        end

        def io_wait(io, events, timeout = nil)
          events
        end

        def kernel_sleep(duration = nil)
          Thread.pass
        end

        def block(blocker, timeout = nil)
          @blocking += 1
          @fiber.transfer
        ensure
          @blocking -= 1
        end

        def unblock(blocker, fiber)
          @ready << fiber
          @output.write(".")
          @output.flush
        rescue IOError
          # Closing the scheduler wakeup pipe should not escape this hook as a
          # pending interrupt on the helper thread.
        end

        def process_wait(pid, flags)
          Thread.new { Process::Status.wait(pid, flags) }.value
        end

        def run
          until @blocking.zero? && @ready.empty?
            until @ready.empty?
              fiber = @ready.pop
              fiber.transfer if fiber.alive?
            end

            break if @blocking.zero?

            if IO.select([@input], nil, nil, 0.01)
              @input.read_nonblock(1024, exception: false)
            end
          end
        end

        def close
          @input.close unless @input.closed?
          @output.close unless @output.closed?
        end
      end

      Thread.report_on_exception = true
      Thread.abort_on_exception = true

      1000.times do
        thread = Thread.new do
          scheduler = Scheduler.new(Fiber.current)
          Fiber.set_scheduler(scheduler)

          fiber = Fiber.new do
            pid = Process.spawn("true")
            _, status = Process.wait2(pid)
            assert_predicate(status, :success?)
          end

          fiber.transfer
          scheduler.run
        ensure
          Fiber.set_scheduler(nil)
          scheduler&.close
        end

        assert_nothing_raised do
          thread.value
        end
      end
    end;
  end

  def test_scheduler_abandoned_io_wait_close_after_thread_exit
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 10)
    begin;
      class Scheduler
        def initialize(fiber = Fiber.current)
          @fiber = fiber
        end

        def io_wait(io, events, timeout = nil)
          @fiber.transfer
        end

        def kernel_sleep(duration = nil)
          @fiber.transfer
        end

        def block(blocker, timeout = nil)
          @fiber.transfer
        end

        def unblock(blocker, fiber)
        end

        def fiber_interrupt(fiber, exception)
          :ignored
        end

        def process_wait(pid, flags)
          Thread.new { Process::Status.wait(pid, flags) }.value
        end

        def close
        end
      end

      begin
        input, output = IO.pipe

        thread = Thread.new do
          Fiber.set_scheduler(Scheduler.new)

          fiber = Fiber.new(blocking: false) do
            input.wait_readable
          end

          fiber.transfer
        ensure
          Fiber.set_scheduler(nil)
        end

        thread.value

        input.close
      ensure
        output&.close unless output&.closed?
        input&.close unless input&.closed?
      end
    end;
  end

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
