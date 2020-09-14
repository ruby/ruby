# frozen_string_literal: true

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

    @urgent = nil

    @lock = Mutex.new
    @locking = 0
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

    while @readable.any? or @writable.any? or @waiting.any? or @locking.positive?
      # Can only handle file descriptors up to 1024...
      readable, writable = IO.select(@readable.keys + [@urgent.first], @writable.keys, [], next_timeout)

      # puts "readable: #{readable}" if readable&.any?
      # puts "writable: #{writable}" if writable&.any?

      readable&.each do |io|
        @readable[io]&.resume
      end

      writable&.each do |io|
        @writable[io]&.resume
      end

      if @waiting.any?
        time = current_time
        waiting = @waiting
        @waiting = {}

        waiting.each do |fiber, timeout|
          if timeout <= time
            fiber.resume
          else
            @waiting[fiber] = timeout
          end
        end
      end

      if @ready.any?
        # Clear out the urgent notification pipe.
        @urgent.first.read_nonblock(1024)

        ready = nil

        @lock.synchronize do
          ready, @ready = @ready, Array.new
        end

        ready.each do |fiber|
          fiber.resume
        end
      end
    end
  ensure
    @urgent.each(&:close)
  end

  def current_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def kernel_sleep(duration = nil)
    @waiting[Fiber.current] = current_time + duration

    Fiber.yield

    return true
  end

  def io_wait(io, events, duration)
    unless (events & IO::READABLE).zero?
      @readable[io] = Fiber.current
    end

    unless (events & IO::WRITABLE).zero?
      @writable[io] = Fiber.current
    end

    Fiber.yield

    @readable.delete(io)
    @writable.delete(io)

    return true
  end

  def mutex_lock(mutex)
    @locking += 1
    Fiber.yield
  ensure
    @locking -= 1
  end

  def mutex_unlock(mutex, fiber)
    @lock.synchronize do
      @ready << fiber

      if @urgent
        @urgent.last.write('.')
      end
    end
  end

  def fiber(&block)
    fiber = Fiber.new(blocking: false, &block)

    fiber.resume

    return fiber
  end
end
