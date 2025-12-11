# frozen_string_literal: true
# Timeout long-running blocks
#
# == Synopsis
#
#   require 'timeout'
#   status = Timeout.timeout(5) {
#     # Something that should be interrupted if it takes more than 5 seconds...
#   }
#
# == Description
#
# Timeout provides a way to auto-terminate a potentially long-running
# operation if it hasn't finished in a fixed amount of time.
#
# == Copyright
#
# Copyright:: (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright:: (C) 2000  Information-technology Promotion Agency, Japan

module Timeout
  # The version
  VERSION = "0.5.0"

  # Internal error raised to when a timeout is triggered.
  class ExitException < Exception
    def exception(*) # :nodoc:
      self
    end
  end

  # Raised by Timeout.timeout when the block times out.
  class Error < RuntimeError
    def self.handle_timeout(message) # :nodoc:
      exc = ExitException.new(message)

      begin
        yield exc
      rescue ExitException => e
        raise new(message) if exc.equal?(e)
        raise
      end
    end
  end

  # :stopdoc:

  # We keep a private reference so that time mocking libraries won't break Timeout.
  GET_TIME = Process.method(:clock_gettime)
  if defined?(Ractor.make_shareable)
    # Ractor.make_shareable(Method) only works on Ruby 4+
    Ractor.make_shareable(GET_TIME) rescue nil
  end
  private_constant :GET_TIME

  class State
    attr_reader :condvar, :queue, :queue_mutex # shared with Timeout.timeout()

    def initialize
      @condvar = ConditionVariable.new
      @queue = Queue.new
      @queue_mutex = Mutex.new

      @timeout_thread = nil
      @timeout_thread_mutex = Mutex.new
    end

    if defined?(Ractor.store_if_absent) && defined?(Ractor.shareable?) && Ractor.shareable?(GET_TIME)
      # Ractor support if
      # 1. Ractor.store_if_absent is available
      # 2. Method object can be shareable (4.0~)
      def self.instance
        Ractor.store_if_absent :timeout_gem_state do
          State.new
        end
      end
    else
      GLOBAL_STATE = State.new

      def self.instance
        GLOBAL_STATE
      end
    end

    def create_timeout_thread
      watcher = Thread.new do
        requests = []
        while true
          until @queue.empty? and !requests.empty? # wait to have at least one request
            req = @queue.pop
            requests << req unless req.done?
          end
          closest_deadline = requests.min_by(&:deadline).deadline

          now = 0.0
          @queue_mutex.synchronize do
            while (now = GET_TIME.call(Process::CLOCK_MONOTONIC)) < closest_deadline and @queue.empty?
              @condvar.wait(@queue_mutex, closest_deadline - now)
            end
          end

          requests.each do |req|
            req.interrupt if req.expired?(now)
          end
          requests.reject!(&:done?)
        end
      end

      if !watcher.group.enclosed? && (!defined?(Ractor.main?) || Ractor.main?)
        ThreadGroup::Default.add(watcher)
      end

      watcher.name = "Timeout stdlib thread"
      watcher.thread_variable_set(:"\0__detached_thread__", true)
      watcher
    end

    def ensure_timeout_thread_created
      unless @timeout_thread&.alive?
        # If the Mutex is already owned we are in a signal handler.
        # In that case, just return and let the main thread create the Timeout thread.
        return if @timeout_thread_mutex.owned?

        @timeout_thread_mutex.synchronize do
          unless @timeout_thread&.alive?
            @timeout_thread = create_timeout_thread
          end
        end
      end
    end
  end
  private_constant :State

  class Request
    attr_reader :deadline

    def initialize(thread, timeout, exception_class, message)
      @thread = thread
      @deadline = GET_TIME.call(Process::CLOCK_MONOTONIC) + timeout
      @exception_class = exception_class
      @message = message

      @mutex = Mutex.new
      @done = false # protected by @mutex
    end

    def done?
      @mutex.synchronize do
        @done
      end
    end

    def expired?(now)
      now >= @deadline
    end

    def interrupt
      @mutex.synchronize do
        unless @done
          @thread.raise @exception_class, @message
          @done = true
        end
      end
    end

    def finished
      @mutex.synchronize do
        @done = true
      end
    end
  end
  private_constant :Request

  # :startdoc:

  # Perform an operation in a block, raising an error if it takes longer than
  # +sec+ seconds to complete.
  #
  # +sec+:: Number of seconds to wait for the block to terminate. Any non-negative number
  #         or nil may be used, including Floats to specify fractional seconds. A
  #         value of 0 or +nil+ will execute the block without any timeout.
  #         Any negative number will raise an ArgumentError.
  # +klass+:: Exception Class to raise if the block fails to terminate
  #           in +sec+ seconds.  Omitting will use the default, Timeout::Error
  # +message+:: Error message to raise with Exception Class.
  #             Omitting will use the default, "execution expired"
  #
  # Returns the result of the block *if* the block completed before
  # +sec+ seconds, otherwise throws an exception, based on the value of +klass+.
  #
  # The exception thrown to terminate the given block cannot be rescued inside
  # the block unless +klass+ is given explicitly. However, the block can use
  # ensure to prevent the handling of the exception.  For that reason, this
  # method cannot be relied on to enforce timeouts for untrusted blocks.
  #
  # If a scheduler is defined, it will be used to handle the timeout by invoking
  # Scheduler#timeout_after.
  #
  # Note that this is both a method of module Timeout, so you can <tt>include
  # Timeout</tt> into your classes so they have a #timeout method, as well as
  # a module method, so you can call it directly as Timeout.timeout().
  def self.timeout(sec, klass = nil, message = nil, &block)   #:yield: +sec+
    return yield(sec) if sec == nil or sec.zero?
    raise ArgumentError, "Timeout sec must be a non-negative number" if 0 > sec

    message ||= "execution expired"

    if Fiber.respond_to?(:current_scheduler) && (scheduler = Fiber.current_scheduler)&.respond_to?(:timeout_after)
      return scheduler.timeout_after(sec, klass || Error, message, &block)
    end

    state = State.instance
    state.ensure_timeout_thread_created

    perform = Proc.new do |exc|
      request = Request.new(Thread.current, sec, exc, message)
      state.queue_mutex.synchronize do
        state.queue << request
        state.condvar.signal
      end
      begin
        return yield(sec)
      ensure
        request.finished
      end
    end

    if klass
      perform.call(klass)
    else
      Error.handle_timeout(message, &perform)
    end
  end

  private def timeout(*args, &block)
    Timeout.timeout(*args, &block)
  end
end
