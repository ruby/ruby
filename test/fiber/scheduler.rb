# frozen_string_literal: true

# This is an example and simplified scheduler for test purposes.
# It is not efficient for a large number of file descriptors as it uses IO.select().
# Production Fiber schedulers should use epoll/kqueue/etc.

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

  def initialize
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

    while @readable.any? or @writable.any? or @waiting.any? or @blocking.any?
      # Can only handle file descriptors up to 1024...
      readable, writable = IO.select(@readable.keys + [@urgent.first], @writable.keys, [], next_timeout)

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
        fiber.resume(events)
      end

      if @waiting.any?
        time = current_time
        waiting, @waiting = @waiting, {}

        waiting.each do |fiber, timeout|
          if fiber.alive?
            if timeout <= time
              fiber.resume
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
          fiber.resume
        end
      end
    end
  end

  def scheduler_close
    close(true)
  end

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

  def process_wait(pid, flags)
    # $stderr.puts [__method__, pid, flags, Fiber.current].inspect

    # This is a very simple way to implement a non-blocking wait:
    Thread.new do
      Process::Status.wait(pid, flags)
    end.value
  end

  def io_wait(io, events, duration)
    # $stderr.puts [__method__, io, events, duration, Fiber.current].inspect

    unless (events & IO::READABLE).zero?
      @readable[io] = Fiber.current
    end

    unless (events & IO::WRITABLE).zero?
      @writable[io] = Fiber.current
    end

    Fiber.yield
  ensure
    @readable.delete(io)
    @writable.delete(io)
  end

  def io_select(...)
    # Emulate the operation using a non-blocking thread:
    Thread.new do
      IO.select(...)
    end.value
  end

  # Used for Kernel#sleep and Thread::Mutex#sleep
  def kernel_sleep(duration = nil)
    # $stderr.puts [__method__, duration, Fiber.current].inspect

    self.block(:sleep, duration)

    return true
  end

  # Used when blocking on synchronization (Thread::Mutex#lock,
  # Thread::Queue#pop, Thread::SizedQueue#push, ...)
  def block(blocker, timeout = nil)
    # $stderr.puts [__method__, blocker, timeout].inspect

    fiber = Fiber.current

    if timeout
      @waiting[fiber] = current_time + timeout
      begin
        Fiber.yield
      ensure
        # Remove from @waiting in the case #unblock was called before the timeout expired:
        @waiting.delete(fiber)
      end
    else
      @blocking[fiber] = true
      begin
        Fiber.yield
      ensure
        @blocking.delete(fiber)
      end
    end
  end

  # Used when synchronization wakes up a previously-blocked fiber
  # (Thread::Mutex#unlock, Thread::Queue#push, ...).
  # This might be called from another thread.
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

  def fiber(&block)
    fiber = Fiber.new(blocking: false, &block)

    fiber.resume

    return fiber
  end

  def address_resolve(hostname)
    Thread.new do
      Addrinfo.getaddrinfo(hostname, nil).map(&:ip_address).uniq
    end.value
  end
end

class IOBufferScheduler < Scheduler
  EAGAIN = -Errno::EAGAIN::Errno

  def io_read(io, buffer, length, offset)
    total = 0
    io.nonblock = true

    while true
      maximum_size = buffer.size - offset
      result = blocking{buffer.read(io, maximum_size, offset)}

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
      maximum_size = buffer.size - offset
      result = blocking{buffer.write(io, maximum_size, offset)}

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

  def blocking(&block)
    Fiber.blocking(&block)
  end
end

class BrokenUnblockScheduler < Scheduler
  def unblock(blocker, fiber)
    super

    raise "Broken unblock!"
  end
end

class SleepingUnblockScheduler < Scheduler
  # This method is invoked when the thread is exiting.
  def unblock(blocker, fiber)
    super

    # This changes the current thread state to `THREAD_RUNNING` which causes `thread_join_sleep` to hang.
    sleep(0.1)
  end
end

class SleepingBlockingScheduler < Scheduler
  def kernel_sleep(duration = nil)
    # Deliberaly sleep in a blocking state which can trigger a deadlock if the implementation is not correct.
    Fiber.blocking{sleep 0.0001}

    self.block(:sleep, duration)

    return true
  end
end
