#
#		thread.rb - thread support classes
#			$Date$
#			by Yukihiro Matsumoto <matz@netlab.co.jp>
#
# Copyright (C) 2001  Yukihiro Matsumoto
# Copyright (C) 2000  Network Applied Communication Laboratory, Inc.
# Copyright (C) 2000  Information-technology Promotion Agency, Japan
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

def Thread.exclusive
  _old = Thread.critical
  begin
    Thread.critical = true
    return yield
  ensure
    Thread.critical = _old
  end
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
    Thread.critical = true
    @locked = false
    begin
      t = @waiting.shift
      t.wakeup if t
    rescue ThreadError
      retry
    end
    Thread.critical = false
    begin
      t.run if t
    rescue ThreadError
    end
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

  def exclusive_unlock
    return unless @locked
    Thread.exclusive do
      @locked = false
      begin
	t = @waiting.shift
	t.wakeup if t
      rescue ThreadError
	retry
      end
      yield
    end
    self
  end
end

class ConditionVariable
  def initialize
    @waiters = []
  end
  
  def wait(mutex)
    mutex.exclusive_unlock do
      @waiters.push(Thread.current)
      Thread.stop
    end
    mutex.lock
  end
  
  def signal
    begin
      t = @waiters.shift
      t.run if t
    rescue ThreadError
      retry
    end
  end
    
  def broadcast
    waiters0 = nil
    Thread.exclusive do
      waiters0 = @waiters.dup
      @waiters.clear
    end
    for t in waiters0
      begin
	t.run
      rescue ThreadError
      end
    end
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
    begin
      t = @waiting.shift
      t.wakeup if t
    rescue ThreadError
      retry
    ensure
      Thread.critical = false
    end
    begin
      t.run if t
    rescue ThreadError
    end
  end
  alias << push
  alias enq push

  def pop(non_block=false)
    while (Thread.critical = true; @que.empty?)
      raise ThreadError, "queue empty" if non_block
      @waiting.push Thread.current
      Thread.stop
    end
    @que.shift
  ensure
    Thread.critical = false
  end
  alias shift pop
  alias deq pop

  def empty?
    @que.empty?
  end

  def clear
    @que.clear
  end

  def length
    @que.length
  end
  def size
    length
  end

  def num_waiting
    @waiting.size
  end
end

class SizedQueue<Queue
  def initialize(max)
    raise ArgumentError, "queue size must be positive" unless max > 0
    @max = max
    @queue_wait = []
    @queue_wait.taint		# enable tainted comunication
    super()
  end

  def max
    @max
  end

  def max=(max)
    Thread.critical = true
    if max <= @max
      @max = max
      Thread.critical = false
    else
      diff = max - @max
      @max = max
      Thread.critical = false
      diff.times do
	begin
	  t = @queue_wait.shift
	  t.run if t
	rescue ThreadError
	  retry
	end
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
  alias << push
  alias enq push

  def pop(*args)
    retval = super
    Thread.critical = true
    if @que.length < @max
      begin
	t = @queue_wait.shift
	t.wakeup if t
      rescue ThreadError
	retry
      ensure
	Thread.critical = false
      end
      begin
	t.run if t
      rescue ThreadError
      end
    end
    retval
  end
  alias shift pop
  alias deq pop

  def num_waiting
    @waiting.size + @queue_wait.size
  end
end
