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
    @blocking = []

    @ios = ObjectSpace::WeakMap.new
  end

  attr :readable
  attr :writable
  attr :waiting
  attr :blocking

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
    while @readable.any? or @writable.any? or @waiting.any?
      # Can only handle file descriptors up to 1024...
      readable, writable = IO.select(@readable.keys, @writable.keys, [], next_timeout)

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
    end
  end

  def for_fd(fd)
    @ios[fd] ||= ::IO.for_fd(fd, autoclose: false)
  end

  def wait_readable(io)
    @readable[io] = Fiber.current

    Fiber.yield

    @readable.delete(io)

    return true
  end

  def wait_readable_fd(fd)
    wait_readable(
      for_fd(fd)
    )
  end

  def wait_writable(io)
    @writable[io] = Fiber.current

    Fiber.yield

    @writable.delete(io)

    return true
  end

  def wait_writable_fd(fd)
    wait_writable(
      for_fd(fd)
    )
  end

  def current_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def wait_sleep(duration = nil)
    @waiting[Fiber.current] = current_time + duration

    Fiber.yield

    return true
  end

  def wait_any(io, events, duration)
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

  def wait_for_single_fd(fd, events, duration)
    wait_any(
      for_fd(fd),
      events,
      duration
    )
  end

  def enter_blocking_region
    # puts "Enter blocking region: #{caller.first}"
  end

  def exit_blocking_region
    # puts "Exit blocking region: #{caller.first}"
    @blocking << caller.first
  end

  def fiber(&block)
    fiber = Fiber.new(blocking: false, &block)

    fiber.resume

    return fiber
  end
end
