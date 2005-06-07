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
  # Wraps a block in Thread.critical, restoring the original value upon exit
  # from the critical section.
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
# Mutex implements a simple semaphore that can be used to coordinate access to
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
  #
  # Creates a new Mutex
  #
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
    @locked
  end

  #
  # Attempts to obtain the lock and returns immediately. Returns +true+ if the
  # lock was granted.
  #
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

  #
  # Attempts to grab the lock and waits if it isn't available.
  #
  def lock
    while (Thread.critical = true; @locked)
      @waiting.push Thread.current
      Thread.stop
    end
    @locked = true
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
  # completes.  See the example under Mutex.
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
  # If the mutex is locked, unlocks the mutex, wakes one waiting thread, and
  # yields in a critical section.
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
# ConditionVariable objects augment class Mutex. Using condition variables,
# it is possible to suspend while in the middle of a critical section until a
# resource becomes available.
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
  #
  # Creates a new ConditionVariable
  #
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
# This class provides a way to synchronize communication between threads.
#
# Example:
#
#   require 'thread'
#   
#   queue = Queue.new
#   
#   producer = Thread.new do
#     5.times do |i|
#       sleep rand(i) # simulate expense
#       queue << i
#       puts "#{i} produced"
#     end
#   end
#   
#   consumer = Thread.new do
#     5.times do |i|
#       value = queue.pop
#       sleep rand(i/2) # simulate expense
#       puts "consumed #{value}"
#     end
#   end
#   
#   consumer.join
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

  #
  # Alias of push
  #
  alias << push

  #
  # Alias of push
  #
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

  #
  # Alias of pop
  #
  alias shift pop

  #
  # Alias of pop
  #
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
  alias size length

  #
  # Returns the number of threads waiting on the queue.
  #
  def num_waiting
    @waiting.size
  end
end

#
# This class represents queues of specified size capacity.  The push operation
# may be blocked if the capacity is full.
#
# See Queue for an example of how a SizedQueue works.
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

  #
  # Pushes +obj+ to the queue.  If there is no space left in the queue, waits
  # until space becomes available.
  #
  def push(obj)
    Thread.critical = true
    while @que.length >= @max
      @queue_wait.push Thread.current
      Thread.stop
      Thread.critical = true
    end
    super
  end

  #
  # Alias of push
  #
  alias << push

  #
  # Alias of push
  #
  alias enq push

  #
  # Retrieves data from the queue and runs a waiting thread, if any.
  #
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

  #
  # Alias of pop
  #
  alias shift pop

  #
  # Alias of pop
  #
  alias deq pop

  #
  # Returns the number of threads waiting on the queue.
  #
  def num_waiting
    @waiting.size + @queue_wait.size
  end
end

# Documentation comments:
#  - How do you make RDoc inherit documentation from superclass?
