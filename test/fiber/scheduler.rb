# frozen_string_literal: true

# This is an example and simplified scheduler for test purposes.
# - It is not efficient for a large number of file descriptors as it uses
#   IO.select().
# - It does not correctly handle multiple calls to `wait` with the same file
#   descriptor and overlapping events.
# - Production fiber schedulers should use epoll/kqueue/etc. Consider using the
#   [`io-event`](https://github.com/socketry/io-event) gem instead of this
#   scheduler if you want something simple to build on.

require 'fiber'
require 'socket'

begin
  require 'io/nonblock'
rescue LoadError
  # Ignore.
end

class Scheduler
  experimental = Warning[:experimental]
  begin
    Warning[:experimental] = false
    IO::Buffer.new(0)
  ensure
    Warning[:experimental] = experimental
  end

  def initialize(fiber = Fiber.current)
    @fiber = fiber

    @readable = {}
    @writable = {}
    @waiting = {}

    @closed = false

    @lock = Thread::Mutex.new
    @blocking = Hash.new.compare_by_identity
    @ready = []

    @urgent = IO.pipe
  end

  attr :readable
  attr :writable
  attr :waiting

  def transfer
    @fiber.transfer
  end

  def next_timeout
    _fiber, timeout = @waiting.min_by{|key, value| value}

    if timeout
      offset = timeout - current_time

      if offset < 0
        return 0
      else
        return offset
      end
    end
  end

  def run
    # $stderr.puts [__method__, Fiber.current].inspect

    readable = writable = nil

    while @readable.any? or @writable.any? or @waiting.any? or @blocking.any?
      # May only handle file descriptors up to 1024...
      begin
        readable, writable = IO.select(@readable.keys + [@urgent.first], @writable.keys, [], next_timeout)
      rescue IOError
        # Ignore - this can happen if the IO is closed while we are waiting.
      end

      # puts "readable: #{readable}" if readable&.any?
      # puts "writable: #{writable}" if writable&.any?

      selected = {}

      readable&.each do |io|
        if fiber = @readable.delete(io)
          @writable.delete(io) if @writable[io] == fiber
          selected[fiber] = IO::READABLE
        elsif io == @urgent.first
          @urgent.first.read_nonblock(1024)
        end
      end

      writable&.each do |io|
        if fiber = @writable.delete(io)
          @readable.delete(io) if @readable[io] == fiber
          selected[fiber] = selected.fetch(fiber, 0) | IO::WRITABLE
        end
      end

      selected.each do |fiber, events|
        fiber.transfer(events)
      end

      if @waiting.any?
        time = current_time
        waiting, @waiting = @waiting, {}

        waiting.each do |fiber, timeout|
          if fiber.alive?
            if timeout <= time
              fiber.transfer
            else
              @waiting[fiber] = timeout
            end
          end
        end
      end

      if @ready.any?
        ready = nil

        @lock.synchronize do
          ready, @ready = @ready, []
        end

        ready.each do |fiber|
          fiber.transfer if fiber.alive?
        end
      end
    end
  end

  # A fiber scheduler hook, invoked when the scheduler goes out of scope.
  def scheduler_close
    close(true)
  end

  # If the `scheduler_close` hook does not exist, this method `close` will be
  # invoked instead when the fiber scheduler goes out of scope. This is legacy
  # behaviour, you should almost certainly use `scheduler_close`. The reason for
  # this, is `scheduler_close` is called when the scheduler goes out of scope,
  # while `close` may be called by the user.
  def close(internal = false)
    # $stderr.puts [__method__, Fiber.current].inspect

    unless internal
      if Fiber.scheduler == self
        return Fiber.set_scheduler(nil)
      end
    end

    if @closed
      raise "Scheduler already closed!"
    end

    self.run
  ensure
    if @urgent
      @urgent.each(&:close)
      @urgent = nil
    end

    @closed ||= true

    # We freeze to detect any unintended modifications after the scheduler is closed:
    self.freeze
  end

  def closed?
    @closed
  end

  def current_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # This hook is invoked by `Timeout.timeout` and related code.
  def timeout_after(duration, klass, message, &block)
    fiber = Fiber.current

    self.fiber do
      sleep(duration)

      if fiber&.alive?
        fiber.raise(klass, message)
      end
    end

    begin
      yield(duration)
    ensure
      fiber = nil
    end
  end

  # This hook is invoked by `Process.wait`, `system`, and backticks.
  def process_wait(pid, flags)
    # $stderr.puts [__method__, pid, flags, Fiber.current].inspect

    # This is a very simple way to implement a non-blocking wait:
    Thread.new do
      Process::Status.wait(pid, flags)
    end.value
  end

  # This hook is invoked by `IO#read` and `IO#write` in the case that `io_read`
  # and `io_write` hooks are not available. This implementation is not
  # completely general, in the sense that calling `io_wait` multiple times with
  # the same `io` and `events` will not work, which is okay for tests but not
  # for real code. Correct fiber schedulers should not have this limitation.
  def io_wait(io, events, duration)
    # $stderr.puts [__method__, io, events, duration, Fiber.current].inspect

    fiber = Fiber.current

    unless (events & IO::READABLE).zero?
      @readable[io] = fiber
      readable = true
    end

    unless (events & IO::WRITABLE).zero?
      @writable[io] = fiber
      writable = true
    end

    if duration
      @waiting[fiber] = current_time + duration
    end

    @fiber.transfer
  ensure
    @waiting.delete(fiber) if duration
    @readable.delete(io) if readable
    @writable.delete(io) if writable
  end

  # This hook is invoked by `IO.select`. Using a thread ensures that the
  # operation does not block the fiber scheduler.
  def io_select(...)
    # Emulate the operation using a non-blocking thread:
    Thread.new do
      IO.select(...)
    end.value
  end

  # This hook is invoked by `Kernel#sleep` and `Thread::Mutex#sleep`.
  def kernel_sleep(duration = nil)
    # $stderr.puts [__method__, duration, Fiber.current].inspect

    self.block(:sleep, duration)

    return true
  end

  # This hook is invoked by blocking options such as `Thread::Mutex#lock`,
  # `Thread::Queue#pop` and `Thread::SizedQueue#push`, which are unblocked by
  # other threads/fibers. To unblock a blocked fiber, you should call `unblock`
  # with the same `blocker` and `fiber` arguments.
  def block(blocker, timeout = nil)
    # $stderr.puts [__method__, blocker, timeout].inspect

    fiber = Fiber.current

    if timeout
      @waiting[fiber] = current_time + timeout
      begin
        @fiber.transfer
      ensure
        # Remove from @waiting in the case #unblock was called before the timeout expired:
        @waiting.delete(fiber)
      end
    else
      @blocking[fiber] = true
      begin
        @fiber.transfer
      ensure
        @blocking.delete(fiber)
      end
    end
  end

  # This method is invoked from a thread or fiber to unblock a fiber that is
  # blocked by `block`. It is expected to be thread safe.
  def unblock(blocker, fiber)
    # $stderr.puts [__method__, blocker, fiber].inspect
    # $stderr.puts blocker.backtrace.inspect
    # $stderr.puts fiber.backtrace.inspect

    @lock.synchronize do
      @ready << fiber
    end

    io = @urgent.last
    io.write_nonblock('.')
  end

  class FiberInterrupt
    def initialize(fiber, exception)
      @fiber = fiber
      @exception = exception
    end

    def alive?
      @fiber.alive?
    end

    def transfer
      @fiber.raise(@exception)
    end
  end

  def fiber_interrupt(fiber, exception)
    @lock.synchronize do
      @ready << FiberInterrupt.new(fiber, exception)
    end

    io = @urgent.last
    io.write_nonblock('.')
  end

  # This hook is invoked by `Fiber.schedule`. Strictly speaking, you should use
  # it to create scheduled fibers, but it is not required in practice;
  # `Fiber.new` is usually sufficient.
  def fiber(&block)
    fiber = Fiber.new(blocking: false, &block)

    fiber.transfer

    return fiber
  end

  # This hook is invoked by `Addrinfo.getaddrinfo`. Using a thread ensures that
  # the operation does not block the fiber scheduler, since `getaddrinfo` is
  # usually provided by `libc` and is blocking.
  def address_resolve(hostname)
    Thread.new do
      Addrinfo.getaddrinfo(hostname, nil).map(&:ip_address).uniq
    end.value
  end

  def blocking_operation_wait(work)
    thread = Thread.new(&work)

    thread.join

    thread = nil
  ensure
    thread&.kill
  end
end

# This scheduler class implements `io_read` and `io_write` hooks which require
# `IO::Buffer`.
class IOBufferScheduler < Scheduler
  EAGAIN = -Errno::EAGAIN::Errno

  def io_read(io, buffer, length, offset)
    total = 0
    io.nonblock = true

    while true
      result = blocking{buffer.read(io, 0, offset)}

      if result > 0
        total += result
        offset += result
        break if total >= length
      elsif result == 0
        break
      elsif result == EAGAIN
        if length > 0
          self.io_wait(io, IO::READABLE, nil)
        else
          return result
        end
      elsif result < 0
        return result
      end
    end

    return total
  end

  def io_write(io, buffer, length, offset)
    total = 0
    io.nonblock = true

    while true
      result = blocking{buffer.write(io, 0, offset)}

      if result > 0
        total += result
        offset += result
        break if total >= length
      elsif result == 0
        break
      elsif result == EAGAIN
        if length > 0
          self.io_wait(io, IO::WRITABLE, nil)
        else
          return result
        end
      elsif result < 0
        return result
      end
    end

    return total
  end

  def io_pread(io, buffer, from, length, offset)
    total = 0
    io.nonblock = true

    while true
      result = blocking{buffer.pread(io, from, 0, offset)}

      if result > 0
        total += result
        offset += result
        from += result
        break if total >= length
      elsif result == 0
        break
      elsif result == EAGAIN
        if length > 0
          self.io_wait(io, IO::READABLE, nil)
        else
          return result
        end
      elsif result < 0
        return result
      end
    end

    return total
  end

  def io_pwrite(io, buffer, from, length, offset)
    total = 0
    io.nonblock = true

    while true
      result = blocking{buffer.pwrite(io, from, 0, offset)}

      if result > 0
        total += result
        offset += result
        from += result
        break if total >= length
      elsif result == 0
        break
      elsif result == EAGAIN
        if length > 0
          self.io_wait(io, IO::WRITABLE, nil)
        else
          return result
        end
      elsif result < 0
        return result
      end
    end

    return total
  end

  def blocking(&block)
    Fiber.blocking(&block)
  end
end

# This scheduler has a broken implementation of `unblock`` in the sense that it
# raises an exception. This is used to test the behavior of the scheduler when
# unblock raises an exception.
class BrokenUnblockScheduler < Scheduler
  def unblock(blocker, fiber)
    super

    raise "Broken unblock!"
  end
end

# This scheduler has a broken implementation of `unblock` in the sense that it
# sleeps. This is used to test the behavior of the scheduler when unblock
# messes with the internal thread state in an unexpected way.
class SleepingUnblockScheduler < Scheduler
  # This method is invoked when the thread is exiting.
  def unblock(blocker, fiber)
    super

    # This changes the current thread state to `THREAD_RUNNING` which causes `thread_join_sleep` to hang.
    sleep(0.1)
  end
end

# This scheduler has a broken implementation of `kernel_sleep` in the sense that
# it invokes a blocking sleep which can cause a deadlock in some cases.
class SleepingBlockingScheduler < Scheduler
  def kernel_sleep(duration = nil)
    # Deliberaly sleep in a blocking state which can trigger a deadlock if the implementation is not correct.
    Fiber.blocking{sleep 0.0001}

    self.block(:sleep, duration)

    return true
  end
end
