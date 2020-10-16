# Scheduler

The scheduler interface is used to intercept blocking operations. A typical
implementation would be a wrapper for a gem like `EventMachine` or `Async`. This
design provides separation of concerns between the event loop implementation
and application code. It also allows for layered schedulers which can perform
instrumentation.

## Interface

This is the interface you need to implement.

~~~ ruby
class Scheduler
  # Wait for the given file descriptor to match the specified events within
  # the specified timeout.
  # @parameter event [Integer] A bit mask of `IO::READABLE`,
  #   `IO::WRITABLE` and `IO::PRIORITY`.
  # @parameter timeout [Numeric] The amount of time to wait for the event in seconds.
  # @returns [Integer] The subset of events that are ready.
  def io_wait(io, events, timeout)
  end

  # Sleep the current task for the specified duration, or forever if not
  # specified.
  # @param duration [Numeric] The amount of time to sleep in seconds.
  def kernel_sleep(duration = nil)
  end

  # Block the calling fiber.
  # @parameter blocker [Object] What we are waiting on, informational only.
  # @parameter timeout [Numeric | Nil] The amount of time to wait for in seconds.
  # @returns [Boolean] Whether the blocking operation was successful or not.
  def block(blocker, timeout = nil)
  end

  # Unblock the specified fiber.
  # @parameter blocker [Object] What we are waiting on, informational only.
  # @parameter fiber [Fiber] The fiber to unblock.
  # @reentrant Thread safe.
  def unblock(blocker, fiber)
  end

  # Intercept the creation of a non-blocking fiber.
  # @returns [Fiber]
  def fiber(&block)
    Fiber.new(blocking: false, &block)
  end

  # Invoked when the thread exits.
  def close
    self.run
  end

  def run
    # Implement event loop here.
  end
end
~~~

Additional hooks may be introduced in the future, we will use feature detection
in order to enable these hooks.

## Non-blocking Execution

The scheduler hooks will only be used in special non-blocking execution
contexts. Non-blocking execution contexts introduce non-determinism because the
execution of scheduler hooks may introduce context switching points into your
program.

### Fibers

Fibers can be used to create non-blocking execution contexts.

~~~ ruby
Fiber.new(blocking: false) do
  puts Fiber.current.blocking? # false

  # May invoke `Fiber.scheduler&.io_wait`.
  io.read(...)

  # May invoke `Fiber.scheduler&.io_wait`.
  io.write(...)

  # Will invoke `Fiber.scheduler&.kernel_sleep`.
  sleep(n)
end.resume
~~~

We also introduce a new method which simplifies the creation of these
non-blocking fibers:

~~~ ruby
Fiber.schedule do
  puts Fiber.current.blocking? # false
end
~~~

The purpose of this method is to allow the scheduler to internally decide the
policy for when to start the fiber, and whether to use symmetric or asymmetric
fibers.

### IO

By default, I/O is non-blocking. Not all operating systems support non-blocking
I/O. Windows is a notable example where socket I/O can be non-blocking but pipe
I/O is blocking. Provided that there *is* a scheduler and the current thread *is
non-blocking*, the operation will invoke the scheduler.

### Mutex

The `Mutex` class can be used in a non-blocking context and is fiber specific.

### ConditionVariable

The `ConditionVariable` class can be used in a non-blocking context and is
fiber-specific.

### Queue / SizedQueue

The `Queue` and `SizedQueue` classses can be used in a non-blocking context and
are fiber-specific.

### Thread

The `Thread#join` operation can be used in a non-blocking context and is
fiber-specific.
