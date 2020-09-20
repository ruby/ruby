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
  def initialize
    @readable = {}
    @writable = {}
    @waiting = {}

    @closed = false

    @lock = Mutex.new
    @blocking = 0
    @ready = []
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
    @urgent = IO.pipe

    while @readable.any? or @writable.any? or @waiting.any? or @blocking.positive?
      # Can only handle file descriptors up to 1024...
      readable, writable = IO.select(@readable.keys + [@urgent.first], @writable.keys, [], next_timeout)

      # puts "readable: #{readable}" if readable&.any?
      # puts "writable: #{writable}" if writable&.any?

      readable&.each do |io|
        if fiber = @readable.delete(io)
          fiber.resume
        elsif io == @urgent.first
          @urgent.first.read_nonblock(1024)
        end
      end

      writable&.each do |io|
        if fiber = @writable.delete(io)
          fiber.resume
        end
      end

      if @waiting.any?
        time = current_time
        waiting, @waiting = @waiting, {}

        waiting.each do |fiber, timeout|
          if timeout <= time
            fiber.resume
          else
            @waiting[fiber] = timeout
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
  ensure
    @urgent.each(&:close)
    @urgent = nil
  end

  def close
    self.run
  ensure
    @closed = true
    
    # We freeze to detect any inadvertant modifications after the scheduler is closed:
    self.freeze
  end

  def closed?
    @closed
  end

  def current_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def io_wait(io, events, duration)
    unless (events & IO::READABLE).zero?
      @readable[io] = Fiber.current
    end

    unless (events & IO::WRITABLE).zero?
      @writable[io] = Fiber.current
    end

    Fiber.yield

    return true
  end

  # Used for Kernel#sleep and Mutex#sleep
  def kernel_sleep(duration = nil)
    # p [__method__, duration]
    if duration
      @waiting[Fiber.current] = current_time + duration
    end

    Fiber.yield

    return true
  end

  # Used when blocking on synchronization (Mutex#lock, Queue#pop, SizedQueue#push, ...)
  def block(blocker, timeout = nil)
    # p [__method__, blocker, timeout]
    @blocking += 1

    if timeout
      @waiting[Fiber.current] = current_time + timeout
    end

    Fiber.yield
  ensure
    @blocking -= 1

    # Remove from @waiting in the case #unblock was called before the timeout expired:
    if timeout
      @waiting.delete(Fiber.current)
    end
  end

  # Used when synchronization wakes up a previously-blocked fiber (Mutex#unlock, Queue#push, ...).
  # This might be called from another thread.
  def unblock(blocker, fiber)
    # p [__method__, blocker, fiber]
    @lock.synchronize do
      @ready << fiber
    end

    if io = @urgent&.last
      io.write_nonblock('.')
    end
  end

  def fiber(&block)
    fiber = Fiber.new(blocking: false, &block)

    fiber.resume

    return fiber
  end
end
