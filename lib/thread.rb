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

class Thread
  #
  # FIXME: not documented in Pickaxe or Nutshell.
  #
  def Thread.exclusive
    _old = Thread.critical
    begin
      Thread.critical = true
      return yield
    ensure
      Thread.critical = _old
    end
  end
end

#
# +Mutex+ implements a simple semaphore that can be used to coordinate access to
# shared data from multiple concurrent threads.
#
# Example:
#
#   require 'thread'
#   semaphore = Mutex.new
#   
#   a = Thread.new {
#     semaphore.synchronize {
#       # access shared resource
#     }
#   }
#   
#   b = Thread.new {
#     semaphore.synchronize {
#       # access shared resource
#     }
#   }
#
class Mutex
  def initialize
    @waiting = []
    @locked = false;
    @waiting.taint		# enable tainted comunication
    self.taint
  end

  #
  # Returns +true+ if this lock is currently held by some thread.
  #
  def locked?
    @locked && true
  end

  #
  # Attempts to obtain the lock and returns immediately. Returns +true+ if the
  # lock was granted.
  #
  def try_lock
    result = false
    Thread.critical = true
    unless @locked
      @locked = Thread.current
      result = true
    end
    Thread.critical = false
    result
  end

  #
  # Attempts to grab the lock and waits if it isn't available.
  #
  def lock
    while (Thread.critical = true; @locked)
      if @locked == Thread.current
        raise ThreadError, "deadlock; recursive locking"
      end
      @waiting.push Thread.current
      Thread.stop
    end
    @locked = Thread.current
    Thread.critical = false
    self
  end

  #
  # Releases the lock. Returns +nil+ if ref wasn't locked.
  #
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

  #
  # Obtains a lock, runs the block, and releases the lock when the block
  # completes.  See the example under +Mutex+.
  #
  def synchronize
    lock
    begin
      yield
    ensure
      unlock
    end
  end

  #
  # FIXME: not documented in Pickaxe/Nutshell.
  #
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

# 
# +ConditionVariable+ objects augment class +Mutex+. Using condition variables,
# it is possible to suspend while in the middle of a critical section until a
# resource becomes available (see the discussion on page 117).
#
# Example:
#
#   require 'thread'
#
#   mutex = Mutex.new
#   resource = ConditionVariable.new
#   
#   a = Thread.new {
#     mutex.synchronize {
#       # Thread 'a' now needs the resource
#       resource.wait(mutex)
#       # 'a' can now have the resource
#     }
#   }
#   
#   b = Thread.new {
#     mutex.synchronize {
#       # Thread 'b' has finished using the resource
#       resource.signal
#     }
#   }
#
class ConditionVariable
  def initialize
    @waiters = []
  end
  
  #
  # Releases the lock held in +mutex+ and waits; reacquires the lock on wakeup.
  #
  def wait(mutex)
    begin
      mutex.exclusive_unlock do
        @waiters.push(Thread.current)
        Thread.stop
      end
    ensure
      mutex.lock
    end
  end
  
  #
  # Wakes up the first thread in line waiting for this lock.
  #
  def signal
    begin
      t = @waiters.shift
      t.run if t
    rescue ThreadError
      retry
    end
  end
    
  #
  # Wakes up all threads waiting for this lock.
  #
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

#
# This class provides a way to communicate data between threads.
#
# TODO: an example (code or English) would really help here.  How do you set up
# a queue between two threads?
#
class Queue
  #
  # Creates a new queue.
  #
  def initialize
    @que = []
    @waiting = []
    @que.taint		# enable tainted comunication
    @waiting.taint
    self.taint
  end

  #
  # Pushes +obj+ to the queue.
  #
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

  #
  # Retrieves data from the queue.  If the queue is empty, the calling thread is
  # suspended until data is pushed onto the queue.  If +non_block+ is true, the
  # thread isn't suspended, and an exception is raised.
  #
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

  #
  # Returns +true+ is the queue is empty.
  #
  def empty?
    @que.empty?
  end

  #
  # Removes all objects from the queue.
  #
  def clear
    @que.clear
  end

  #
  # Returns the length of the queue.
  #
  def length
    @que.length
  end

  #
  # Alias of length.
  #
  def size
    length
  end

  #
  # Returns the number of threads waiting on the queue.
  #
  def num_waiting
    @waiting.size
  end
end

#
# This class represents queues of specified size capacity.  The +push+ operation
# may be blocked if the capacity is full.
#
class SizedQueue<Queue
  #
  # Creates a fixed-length queue with a maximum size of +max+.
  #
  def initialize(max)
    raise ArgumentError, "queue size must be positive" unless max > 0
    @max = max
    @queue_wait = []
    @queue_wait.taint		# enable tainted comunication
    super()
  end

  #
  # Returns the maximum size of the queue.
  #
  def max
    @max
  end

  #
  # Sets the maximum size of the queue.
  #
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

# Documentation comments:
#  - SizedQueue #push and #pop deserve some documentation, as they are different
#    from the Queue implementations.
#  - Some methods are not documented in Pickaxe/Nutshell, and are therefore not
#    documented here.  See FIXME notes.
#  - Reference to Pickaxe page numbers should be replaced with either a section
#    name or a summary.
#  - How do you document aliases?
#  - How do you make RDoc inherit documentation from superclass?
