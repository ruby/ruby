#
#		thread.rb - thread support classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>
#

unless defined? Thread
  fail "Thread not available for this ruby interpreter"
end

unless defined? ThreadError
  class ThreadError<StandardError
  end
end

if $DEBUG
  Thread.abort_on_exception = true
end

class Mutex
  def initialize
    @waiting = []
    @locked = false;
    @waiting.taint		# enable tainted comunication
    self.taint
  end

  def locked?
    @locked
  end

  def try_lock
    result = false
    Thread.critical = true
    unless @locked
      @locked = true
      result = true
    end
    Thread.critical = false
    result
  end

  def lock
    while (Thread.critical = true; @locked)
      @waiting.push Thread.current
      Thread.stop
    end
    @locked = true
    Thread.critical = false
    self
  end

  def unlock
    return unless @locked
    Thread.critical = TRUE
    t = @waiting.shift
    @locked = FALSE
    Thread.critical = FALSE
    t.run if t
    self
  end

  def synchronize
    lock
    begin
      yield
    ensure
      unlock
    end
  end
end

class ConditionVariable
  def initialize
    @waiters = []
    @waiters_mutex = Mutex.new
    @waiters.taint		# enable tainted comunication
    self.taint
  end
  
  def wait(mutex)
    mutex.unlock
    @waiters_mutex.synchronize {
      @waiters.push(Thread.current)
    }
    Thread.stop
    mutex.lock
  end
  
  def signal
    @waiters_mutex.synchronize {
      t = @waiters.shift
      t.run if t
    }
  end
    
  def broadcast
    @waiters_mutex.synchronize {
      for t in @waiters
	t.run
      end
      @waiters.clear
    }
  end
end

class Queue
  def initialize
    @que = []
    @waiting = []
    @que.taint		# enable tainted comunication
    @waiting.taint
    self.taint
  end

  def push(obj)
    Thread.critical = true
    @que.push obj
    t = @waiting.shift
    Thread.critical = false
    t.run if t
  end

  def pop non_block=false
    Thread.critical = true
    begin
      loop do
	if @que.length == 0
	  if non_block
	    raise ThreadError, "queue empty"
	  end
	  @waiting.push Thread.current
	  Thread.stop
	else
	  return @que.shift
	end
      end
    ensure
      Thread.critical = false
    end
  end

  def empty?
    @que.length == 0
  end

  def length
    @que.length
  end
  alias size length


  def num_waiting
    @waiting.size
  end
end

class SizedQueue<Queue
  def initialize(max)
    @max = max
    @queue_wait = []
    @queue_wait.taint		# enable tainted comunication
    super()
  end

  def max
    @max
  end

  def max=(max)
    Thread.critical = TRUE
    if @max >= max
      @max = max
      Thread.critical = FALSE
    else
      diff = max - @max
      @max = max
      Thread.critical = FALSE
      diff.times do
	t = @queue_wait.shift
	t.run if t
      end
    end
    max
  end

  def push(obj)
    Thread.critical = true
    while @que.length >= @max
      @queue_wait.push Thread.current
      Thread.stop
      Thread.critical = true
    end
    super
  end

  def pop(*args)
    Thread.critical = true
    if @que.length < @max
      t = @queue_wait.shift
      t.run if t
    end
    super
  end

  def num_waiting
    @waiting.size + @queue_wait.size
  end
end
