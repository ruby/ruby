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
  VERSION = "0.6.0"

  # Internal exception raised to when a timeout is triggered.
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
      # Threads unexpectedly inherit the interrupt mask: https://github.com/ruby/timeout/issues/41
      # So reset the interrupt mask to the default one for the timeout thread
      Thread.handle_interrupt(Object => :immediate) do
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
    end

    def ensure_timeout_thread_created
      unless @timeout_thread&.alive?
        # If the Mutex is already owned we are in a signal handler.
        # In that case, just return and let the main thread create the Timeout thread.
        return if @timeout_thread_mutex.owned?

        Sync.synchronize @timeout_thread_mutex do
          unless @timeout_thread&.alive?
            @timeout_thread = create_timeout_thread
          end
        end
      end
    end

    def add_request(request)
      Sync.synchronize @queue_mutex do
        @queue << request
        @condvar.signal
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

    # Only called by the timeout thread, so does not need Sync.synchronize
    def done?
      @mutex.synchronize do
        @done
      end
    end

    def expired?(now)
      now >= @deadline
    end

    # Only called by the timeout thread, so does not need Sync.synchronize
    def interrupt
      @mutex.synchronize do
        unless @done
          @thread.raise @exception_class, @message
          @done = true
        end
      end
    end

    def finished
      Sync.synchronize @mutex do
        @done = true
      end
    end
  end
  private_constant :Request

  module Sync
    # Calls mutex.synchronize(&block) but if that fails on CRuby due to being in a trap handler,
    # run mutex.synchronize(&block) in a separate Thread instead.
    def self.synchronize(mutex, &block)
      begin
        mutex.synchronize(&block)
      rescue ThreadError => e
        raise e unless e.message == "can't be called from trap context"
        # Workaround CRuby issue https://bugs.ruby-lang.org/issues/19473
        # which raises on Mutex#synchronize in trap handler.
        # It's expensive to create a Thread just for this,
        # but better than failing.
        Thread.new {
          mutex.synchronize(&block)
        }.join
      end
    end
  end
  private_constant :Sync

  # :startdoc:

  # Perform an operation in a block, raising an exception if it takes longer than
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
  # +sec+ seconds, otherwise raises an exception, based on the value of +klass+.
  #
  # The exception raised to terminate the given block is the given +klass+, or
  # Timeout::ExitException if +klass+ is not given. The reason for that behavior
  # is that Timeout::Error inherits from RuntimeError and might be caught unexpectedly by `rescue`.
  # Timeout::ExitException inherits from Exception so it will only be rescued by `rescue Exception`.
  # Note that the Timeout::ExitException is translated to a Timeout::Error once it reaches the Timeout.timeout call,
  # so outside that call it will be a Timeout::Error.
  #
  # In general, be aware that the code block may rescue the exception, and in such a case not respect the timeout.
  # Also, the block can use +ensure+ to prevent the handling of the exception.
  # For those reasons, this method cannot be relied on to enforce timeouts for untrusted blocks.
  #
  # If a scheduler is defined, it will be used to handle the timeout by invoking
  # Scheduler#timeout_after.
  #
  # Note that this is both a method of module Timeout, so you can <tt>include
  # Timeout</tt> into your classes so they have a #timeout method, as well as
  # a module method, so you can call it directly as Timeout.timeout().
  #
  # ==== Ensuring the exception does not fire inside ensure blocks
  #
  # When using Timeout.timeout it can be desirable to ensure the timeout exception does not fire inside an +ensure+ block.
  # The simplest and best way to do so it to put the Timeout.timeout call inside the body of the begin/ensure/end:
  #
  #     begin
  #       Timeout.timeout(sec) { some_long_operation }
  #     ensure
  #       cleanup # safe, cannot be interrupt by timeout
  #     end
  #
  # If that is not feasible, e.g. if there are +ensure+ blocks inside +some_long_operation+,
  # they need to not be interrupted by timeout, and it's not possible to move these ensure blocks outside,
  # one can use Thread.handle_interrupt to delay the timeout exception like so:
  #
  #     Thread.handle_interrupt(Timeout::Error => :never) {
  #       Timeout.timeout(sec, Timeout::Error) do
  #         setup # timeout cannot happen here, no matter how long it takes
  #         Thread.handle_interrupt(Timeout::Error => :immediate) {
  #           some_long_operation # timeout can happen here
  #         }
  #       ensure
  #         cleanup # timeout cannot happen here, no matter how long it takes
  #       end
  #     }
  #
  # An important thing to note is the need to pass an exception klass to Timeout.timeout,
  # otherwise it does not work. Specifically, using +Thread.handle_interrupt(Timeout::ExitException => ...)+
  # is unsupported and causes subtle errors like raising the wrong exception outside the block, do not use that.
  #
  # Note that Thread.handle_interrupt is somewhat dangerous because if setup or cleanup hangs
  # then the current thread will hang too and the timeout will never fire.
  # Also note the block might run for longer than +sec+ seconds:
  # e.g. some_long_operation executes for +sec+ seconds + whatever time cleanup takes.
  #
  # If you want the timeout to only happen on blocking operations one can use :on_blocking
  # instead of :immediate. However, that means if the block uses no blocking operations after +sec+ seconds,
  # the block will not be interrupted.
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
      state.add_request(request)
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
