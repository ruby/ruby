##
# The TimedStack manages a pool of homogeneous connections (or any resource
# you wish to manage). Connections are created lazily up to a given maximum
# number.
#
# Examples:
#
#    ts = TimedStack.new(size: 1) { MyConnection.new }
#
#    # fetch a connection
#    conn = ts.pop
#
#    # return a connection
#    ts.push conn
#
#    conn = ts.pop
#    ts.pop timeout: 5
#    #=> raises Bundler::ConnectionPool::TimeoutError after 5 seconds
class Bundler::ConnectionPool::TimedStack
  attr_reader :max

  ##
  # Creates a new pool with +size+ connections that are created from the given
  # +block+.
  def initialize(size: 0, &block)
    @create_block = block
    @created = 0
    @que = []
    @max = size
    @mutex = Thread::Mutex.new
    @resource = Thread::ConditionVariable.new
    @shutdown_block = nil
  end

  ##
  # Returns +obj+ to the stack. Additional kwargs are ignored in TimedStack but may be
  # used by subclasses that extend TimedStack.
  def push(obj, **)
    @mutex.synchronize do
      if @shutdown_block
        @created -= 1 unless @created == 0
        @shutdown_block.call(obj)
      else
        store_connection obj, **
      end

      @resource.broadcast
    end
  end
  alias_method :<<, :push

  ##
  # Retrieves a connection from the stack. If a connection is available it is
  # immediately returned. If no connection is available within the given
  # timeout a Bundler::ConnectionPool::TimeoutError is raised.
  #
  # @option options [Float] :timeout (0.5) Wait this many seconds for an available entry
  # @option options [Class] :exception (Bundler::ConnectionPool::TimeoutError) Exception class to raise
  #   if an entry was not available within the timeout period. Use `exception: false` to return nil.
  #
  # Other options may be used by subclasses that extend TimedStack.
  def pop(timeout: 0.5, exception: Bundler::ConnectionPool::TimeoutError, **)
    deadline = current_time + timeout
    @mutex.synchronize do
      loop do
        raise Bundler::ConnectionPool::PoolShuttingDownError if @shutdown_block
        if (conn = try_fetch_connection(**))
          return conn
        end

        connection = try_create(**)
        return connection if connection

        to_wait = deadline - current_time
        if to_wait <= 0
          if exception
            raise exception, "Waited #{timeout} sec, #{length}/#{@max} available"
          else
            return nil
          end
        end
        @resource.wait(@mutex, to_wait)
      end
    end
  end

  ##
  # Shuts down the TimedStack by passing each connection to +block+ and then
  # removing it from the pool. Attempting to checkout a connection after
  # shutdown will raise +Bundler::ConnectionPool::PoolShuttingDownError+ unless
  # +:reload+ is +true+.
  def shutdown(reload: false, &block)
    raise ArgumentError, "shutdown must receive a block" unless block

    @mutex.synchronize do
      @shutdown_block = block
      @resource.broadcast

      shutdown_connections
      @shutdown_block = nil if reload
    end
  end

  ##
  # Reaps connections that were checked in more than +idle_seconds+ ago.
  def reap(idle_seconds:)
    raise ArgumentError, "reap must receive a block" unless block_given?
    raise ArgumentError, "idle_seconds must be a number" unless idle_seconds.is_a?(Numeric)
    raise Bundler::ConnectionPool::PoolShuttingDownError if @shutdown_block

    count = idle
    count.times do
      conn = @mutex.synchronize do
        raise Bundler::ConnectionPool::PoolShuttingDownError if @shutdown_block
        reserve_idle_connection(idle_seconds)
      end
      break unless conn

      yield conn
    end
  end

  ##
  # Returns +true+ if there are no available connections.
  def empty?
    (@created - @que.length) >= @max
  end

  ##
  # The number of connections available on the stack.
  def length
    @max - @created + @que.length
  end

  ##
  # The number of connections created and available on the stack.
  def idle
    @que.length
  end

  ##
  # Reduce the created count
  def decrement_created
    @created -= 1 unless @created == 0
  end

  private

  def current_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must returns a connection from the stack if one exists. Allows
  # subclasses with expensive match/search algorithms to avoid double-handling
  # their stack.
  def try_fetch_connection(**)
    connection_stored?(**) && fetch_connection(**)
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must returns true if a connection is available on the stack.
  def connection_stored?(**)
    !@que.empty?
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must return a connection from the stack.
  def fetch_connection(**)
    @que.pop&.first
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must shut down all connections on the stack.
  def shutdown_connections(**)
    while (conn = try_fetch_connection(**))
      @created -= 1 unless @created == 0
      @shutdown_block.call(conn)
    end
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method returns the oldest idle connection if it has been idle for more than idle_seconds.
  # This requires that the stack is kept in order of checked in time (oldest first).
  def reserve_idle_connection(idle_seconds)
    return unless idle_connections?(idle_seconds)

    @created -= 1 unless @created == 0

    # Most active elements are at the tail of the array.
    # Most idle will be at the head so `shift` rather than `pop`.
    @que.shift.first
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # Returns true if the first connection in the stack has been idle for more than idle_seconds
  def idle_connections?(idle_seconds)
    return unless connection_stored?
    # Most idle will be at the head so `first`
    age = (current_time - @que.first.last)
    age > idle_seconds
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must return +obj+ to the stack.
  def store_connection(obj, **)
    @que.push [obj, current_time]
  end

  ##
  # This is an extension point for TimedStack and is called with a mutex.
  #
  # This method must create a connection if and only if the total number of
  # connections allowed has not been met.
  def try_create(**)
    unless @created == @max
      object = @create_block.call
      @created += 1
      object
    end
  end
end
