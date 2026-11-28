# frozen_string_literal: true
require 'test/unit'
require_relative 'scheduler'

class TestFiberIO < Test::Unit::TestCase
  include ParkedWaiterAssertions

  MESSAGE = "Hello World"

  def test_read
    omit unless defined?(UNIXSocket)

    i, o = UNIXSocket.pair
    if RUBY_PLATFORM =~ /mswin|mingw/
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
        if RUBY_PLATFORM =~ /mswin|mingw/
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
    omit "a closed peer does not make the next write fail on Windows" if RUBY_PLATFORM =~ /mswin|mingw/

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

    Socket.pair(:UNIX, :STREAM) do |i, o|
      if RUBY_PLATFORM =~ /mswin|mingw/
        i.nonblock = true
        o.nonblock = true
      end

      reading_thread = Thread.new do
        Thread.current.report_on_exception = false
        i.wait_readable
      end

      scheduler_thread = Thread.new do
        # Wait until the reading thread is blocked on read:
        Thread.pass until reading_thread.status == "sleep"

        scheduler = Scheduler.new
        Fiber.set_scheduler scheduler
        Fiber.schedule do
          i.close
        end
      end

      assert_raise(IOError) { reading_thread.join }
      refute_nil scheduler_thread.join(5), "expected thread to terminate within 5 seconds"

      assert_predicate(i, :closed?)
    ensure
      scheduler_thread&.kill
      scheduler_thread&.join rescue nil
      reading_thread&.kill
      reading_thread&.join rescue nil
    end
  end

  PIPE = "IO.pipe"
  PIPE_WAIT_READABLE = "->(pipe) { pipe[0].wait_readable }"
  PIPE_READ = "->(pipe) { pipe[0].read(1) }"
  PIPE_CLOSE = "->(pipe) { pipe.each(&:close) }"

  # A scheduler fiber parked forever in an IO wait was collected while its
  # on-stack blocking operation stayed in the IO's list; close then read it.
  def test_wait_readable_from_collected_fiber
    assert_parked_waiter_released(PIPE, PIPE_WAIT_READABLE, PIPE_CLOSE)
  end

  def test_read_from_collected_fiber
    assert_parked_waiter_released(PIPE, PIPE_READ, PIPE_CLOSE)
  end

  def test_wait_readable_from_collected_fiber_old_io
    assert_parked_waiter_released(PIPE, PIPE_WAIT_READABLE, PIPE_CLOSE, old_holder: true)
  end

  def test_wait_readable_from_collected_fiber_during_incremental_mark
    assert_parked_waiter_released(PIPE, PIPE_WAIT_READABLE, PIPE_CLOSE, incremental: true)
  end

  # The fiber was non-blocking when it registered the wait, so the IO must
  # still release it although it is blocking when collected.
  def test_wait_readable_from_fiber_parked_while_blocking
    assert_parked_waiter_released(PIPE, PIPE_WAIT_READABLE, PIPE_CLOSE, park_blocking: true)
  end

  # The parked fiber outlives its thread; close used to wait for its operation
  # to finish and die with "No live threads left. Deadlock?".
  def test_wait_readable_from_fiber_of_dead_thread
    assert_parked_waiter_released(PIPE, PIPE_WAIT_READABLE, PIPE_CLOSE, keep_fiber: true)
  end

  # The owner of the operation close is waiting on can never run again only
  # after close started, so close used to wait forever.
  def assert_close_returns_after_owner_abandons(keep_fiber:)
    assert_separately([], <<~RUBY, timeout: 30)
      $parked = []
      class ParkingScheduler
        def initialize = @main = Fiber.current
        def block(blocker, timeout = nil)
          $parked << Fiber.current if #{keep_fiber}
          @main.transfer
        end
        def unblock(blocker, fiber) = nil
        def kernel_sleep(duration = nil) = block(:sleep, duration)
        def io_wait(io, events, timeout) = block(:io_wait, timeout)
        def fiber_interrupt(fiber, exception) = nil
        def close = nil
        def fiber(&) = Fiber.new(blocking: false, &).tap(&:transfer)
      end

      r, w = IO.pipe
      release = Thread::Queue.new
      owner = Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        Fiber.schedule { r.wait_readable }
        release.pop
      end
      Thread.pass until owner.status == "sleep"

      closer = Thread.new { r.close }
      Thread.pass until closer.status == "sleep"

      release.push(nil)
      owner.join
      GC.start
      assert_not_nil(closer.join(10), "close did not return")
      assert_predicate(r, :closed?)
      w.close
    RUBY
  end

  def test_close_returns_when_owner_thread_exits_during_close
    assert_close_returns_after_owner_abandons(keep_fiber: true)
  end

  def test_close_returns_when_owner_fiber_collected_during_close
    assert_close_returns_after_owner_abandons(keep_fiber: false)
  end

  # A scheduler fiber parks in close's wait and its thread exits. The owner's
  # operation then exits and must not wake (or, once collected, read) the closer.
  def assert_operation_exits_after_closer_abandons(keep_closer:)
    assert_separately([{"MallocScribble" => "1"}], <<~RUBY, timeout: 30)
      class ParkingScheduler
        def initialize = @main = Fiber.current
        def block(blocker, timeout = nil) = @main.transfer
        def unblock(blocker, fiber) = nil
        def kernel_sleep(duration = nil) = block(:sleep, duration)
        def io_wait(io, events, timeout) = block(:io_wait, timeout)
        def fiber_interrupt(fiber, exception) = nil
        def close = nil
        def fiber(&) = Fiber.new(blocking: false, &).tap(&:transfer)
      end

      r, w = IO.pipe
      go = Thread::Queue.new
      owner = Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        f = Fiber.schedule do
          r.wait_readable
        rescue IOError
        end
        go.pop
        f.transfer
      end
      Thread.pass until owner.status == "sleep"

      $closer = ObjectSpace::WeakMap.new
      Thread.new do
        Fiber.set_scheduler(ParkingScheduler.new)
        Fiber.schedule do
          $closer[:f] = Fiber.current
          $keep = Fiber.current if #{keep_closer}
          r.close
        end
      end.join

      # Allocating a fiber here could reuse the freed closer and hide a use after free.
      GC.start
      omit "closer not collected" unless #{keep_closer} || !$closer.key?(:f)

      go.push(nil)
      assert_nothing_raised { owner.join }
      w.close
    RUBY
  end

  def test_operation_exits_after_closer_thread_exits
    assert_operation_exits_after_closer_abandons(keep_closer: true)
  end

  def test_operation_exits_after_closer_fiber_collected
    assert_operation_exits_after_closer_abandons(keep_closer: false)
  end
end
