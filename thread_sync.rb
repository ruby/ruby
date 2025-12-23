# frozen_string_literal: true

class Thread
  class Queue
    # call-seq:
    #   pop(non_block=false, timeout: nil)
    #
    # Retrieves data from the queue.
    #
    # If the queue is empty, the calling thread is suspended until data is pushed
    # onto the queue. If +non_block+ is true, the thread isn't suspended, and
    # +ThreadError+ is raised.
    #
    # If +timeout+ seconds have passed and no data is available +nil+ is
    # returned. If +timeout+ is +0+ it returns immediately.
    def pop(non_block = false, timeout: nil)
      if non_block && timeout
        raise ArgumentError, "can't set a timeout if non_block is enabled"
      end
      Primitive.rb_queue_pop(non_block, timeout)
    end
    alias_method :deq, :pop
    alias_method :shift, :pop
  end

  class SizedQueue
    # call-seq:
    #   pop(non_block=false, timeout: nil)
    #
    # Retrieves data from the queue.
    #
    # If the queue is empty, the calling thread is suspended until data is
    # pushed onto the queue. If +non_block+ is true, the thread isn't
    # suspended, and +ThreadError+ is raised.
    #
    # If +timeout+ seconds have passed and no data is available +nil+ is
    # returned. If +timeout+ is +0+ it returns immediately.
    def pop(non_block = false, timeout: nil)
      if non_block && timeout
        raise ArgumentError, "can't set a timeout if non_block is enabled"
      end
      Primitive.rb_szqueue_pop(non_block, timeout)
    end
    alias_method :deq, :pop
    alias_method :shift, :pop

    # call-seq:
    #   push(object, non_block=false, timeout: nil)
    #   enq(object, non_block=false, timeout: nil)
    #   <<(object)
    #
    # Pushes +object+ to the queue.
    #
    # If there is no space left in the queue, waits until space becomes
    # available, unless +non_block+ is true.  If +non_block+ is true, the
    # thread isn't suspended, and +ThreadError+ is raised.
    #
    # If +timeout+ seconds have passed and no space is available +nil+ is
    # returned. If +timeout+ is +0+ it returns immediately.
    # Otherwise it returns +self+.
    def push(object, non_block = false, timeout: nil)
      if non_block && timeout
        raise ArgumentError, "can't set a timeout if non_block is enabled"
      end
      Primitive.rb_szqueue_push(object, non_block, timeout)
    end
    alias_method :enq, :push
    alias_method :<<, :push
  end

  class Mutex
    # call-seq:
    #    Thread::Mutex.new   -> mutex
    #
    # Creates a new Mutex
    def initialize
    end

    # call-seq:
    #    mutex.locked?  -> true or false
    #
    # Returns +true+ if this lock is currently held by some thread.
    def locked?
      Primitive.cexpr! %q{ RBOOL(mutex_locked_p(mutex_ptr(self))) }
    end

    # call-seq:
    #    mutex.owned?  -> true or false
    #
    # Returns +true+ if this lock is currently held by current thread.
    def owned?
      Primitive.rb_mut_owned_p
    end

    # call-seq:
    #    mutex.lock  -> self
    #
    # Attempts to grab the lock and waits if it isn't available.
    # Raises +ThreadError+ if +mutex+ was locked by the current thread.
    def lock
      Primitive.rb_mut_lock
    end

    # call-seq:
    #    mutex.try_lock  -> true or false
    #
    # Attempts to obtain the lock and returns immediately. Returns +true+ if the
    # lock was granted.
    def try_lock
      Primitive.rb_mut_trylock
    end

    # call-seq:
    #    mutex.lock  -> self
    #
    # Attempts to grab the lock and waits if it isn't available.
    # Raises +ThreadError+ if +mutex+ was locked by the current thread.
    def unlock
      Primitive.rb_mut_unlock
    end

    # call-seq:
    #    mutex.synchronize { ... }    -> result of the block
    #
    # Obtains a lock, runs the block, and releases the lock when the block
    # completes.  See the example under Thread::Mutex.
    def synchronize
      raise ThreadError, "must be called with a block" unless defined?(yield)

      Primitive.rb_mut_synchronize
    end

    # call-seq:
    #    mutex.sleep(timeout = nil)    -> number or nil
    #
    # Releases the lock and sleeps +timeout+ seconds if it is given and
    # non-nil or forever.  Raises +ThreadError+ if +mutex+ wasn't locked by
    # the current thread.
    #
    # When the thread is next woken up, it will attempt to reacquire
    # the lock.
    #
    # Note that this method can wakeup without explicit Thread#wakeup call.
    # For example, receiving signal and so on.
    #
    # Returns the slept time in seconds if woken up, or +nil+ if timed out.
    def sleep(timeout = nil)
      Primitive.rb_mut_sleep(timeout)
    end
  end

  class ConditionVariable
    # Document-method: ConditionVariable::new
    #
    # Creates a new condition variable instance.
    def initialize
    end

    undef_method :initialize_copy

    # :nodoc:
    def marshal_dump
      raise TypeError, "can't dump #{self.class}"
    end

    # Document-method: Thread::ConditionVariable#signal
    #
    # Wakes up the first thread in line waiting for this lock.
    def signal
      Primitive.rb_condvar_signal
    end

    # Document-method: Thread::ConditionVariable#broadcast
    #
    # Wakes up all threads waiting for this lock.
    def broadcast
      Primitive.rb_condvar_broadcast
    end

    # Document-method: Thread::ConditionVariable#wait
    # call-seq: wait(mutex, timeout=nil)
    #
    # Releases the lock held in +mutex+ and waits; reacquires the lock on wakeup.
    #
    # If +timeout+ is given, this method returns after +timeout+ seconds passed,
    # even if no other thread doesn't signal.
    #
    # This method may wake up spuriously due to underlying implementation details.
    #
    # Returns the slept result on +mutex+.
    def wait(mutex, timeout=nil)
      Primitive.rb_condvar_wait(mutex, timeout)
    end
  end
end
