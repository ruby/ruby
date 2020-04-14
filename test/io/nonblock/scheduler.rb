# frozen_string_literal: true

require 'fiber'

begin
  require 'io/nonblock'
rescue LoadError
  # Ignore.
end

class Scheduler
  class Condition
    def initialize
      @waiting = []
      @signalled = false
    end

    def signal
      @signalled = true

      while fiber = @waiting.shift
        fiber.resume
      end
    end

    def wait
      unless @signalled
        @waiting << Fiber.current
        Fiber.yield
      end
    end
  end
  
  def initialize
    @readable = {}
    @writable = {}
    @waiting = {}
    @blocking = []
  end

  attr :fiber

  attr :readable
  attr :writable
  attr :waiting
  attr :blocking

  def next_timeout
    fiber, timeout = @waiting.min_by{|key, value| value}

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

  def wait_readable(fd)
    io = IO.for_fd(fd, autoclose: false)

    @readable[io] = Fiber.current

    Fiber.yield

    @readable.delete(io)

    return true
  end

  def wait_writable(fd)
    io = IO.for_fd(fd, autoclose: false)

    @writable[io] = Fiber.current

    Fiber.yield

    @writable.delete(io)

    return true
  end

  def current_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def wait_sleep(duration = nil)
    @waiting[Fiber.current] = current_time + duration

    Fiber.yield

    return true
  end

  def wait_for_single_fd(fd, events, duration)
    # puts "wait_for_single_fd(#{fd}, #{events}, #{duration})"
    io = IO.for_fd(fd, autoclose: false)

    unless (events & IO::WAIT_READABLE).zero?
      @readable[io] = Fiber.current
    end

    unless (events & IO::WAIT_WRITABLE).zero?
      @writable[io] = Fiber.current
    end

    Fiber.yield

    @readable.delete(io)
    @writable.delete(io)

    return true
  end

  def enter_blocking_region
    # puts "Enter blocking region: #{caller.first}"
  end

  def exit_blocking_region
    # puts "Exit blocking region: #{caller.first}"
    @blocking << caller.first
  end

  def fiber(&block)
    Fiber.new(blocking: false, &block)
  end
end
