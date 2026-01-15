# frozen_string_literal: true

class Thread
  #  The Thread::Queue class implements multi-producer, multi-consumer
  #  queues.  It is especially useful in threaded programming when
  #  information must be exchanged safely between multiple threads. The
  #  Thread::Queue class implements all the required locking semantics.
  #
  #  The class implements FIFO (first in, first out) type of queue.
  #  In a FIFO queue, the first tasks added are the first retrieved.
  #
  #  Example:
  #
  #    	queue = Thread::Queue.new
  #
  #	    producer = Thread.new do
  #	      5.times do |i|
  #	        sleep rand(i) # simulate expense
  #	        queue << i
  #	        puts "#{i} produced"
  #	      end
  #	    end
  #
  #	    consumer = Thread.new do
  #	      5.times do |i|
  #	        value = queue.pop
  #	        sleep rand(i/2) # simulate expense
  #	        puts "consumed #{value}"
  #	      end
  #	    end
  #
  #     consumer.join
  class Queue
    # Document-method: Queue::new
    #
    # call-seq:
    #   Thread::Queue.new -> empty_queue
    #   Thread::Queue.new(enumerable) -> queue
    #
    # Creates a new queue instance, optionally using the contents of an +enumerable+
    # for its initial state.
    #
    # Example:
    #
    #    	q = Thread::Queue.new
    #     #=> #<Thread::Queue:0x00007ff7501110d0>
    #     q.empty?
    #     #=> true
    #
    #    	q = Thread::Queue.new([1, 2, 3])
    #    	#=> #<Thread::Queue:0x00007ff7500ec500>
    #     q.empty?
    #     #=> false
    #     q.pop
    #     #=> 1
    def initialize(enumerable = nil)
      Primitive.queue_initialize(enumerable)
    end

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

    undef_method :initialize_copy

    # call-seq:
    #   push(object)
    #   enq(object)
    #   <<(object)
    #
    # Pushes the given +object+ to the queue.
    def push(object)
      Primitive.cexpr!('queue_do_push(self, queue_ptr(self), object)')
    end
    alias_method :enq, :push
    alias_method :<<, :push

    # call-seq:
    #   close
    #
    # Closes the queue. A closed queue cannot be re-opened.
    #
    # After the call to close completes, the following are true:
    #
    # - +closed?+ will return true
    #
    # - +close+ will be ignored.
    #
    # - calling enq/push/<< will raise a +ClosedQueueError+.
    #
    # - when +empty?+ is false, calling deq/pop/shift will return an object
    #   from the queue as usual.
    # - when +empty?+ is true, deq(false) will not suspend the thread and will return nil.
    #   deq(true) will raise a +ThreadError+.
    #
    # ClosedQueueError is inherited from StopIteration, so that you can break loop block.
    #
    # Example:
    #
    #    	q = Thread::Queue.new
    #      Thread.new{
    #        while e = q.deq # wait for nil to break loop
    #          # ...
    #        end
    #      }
    #      q.close
    def close
      Primitive.cstmt! %{
        if (!queue_closed_p(self)) {
            FL_SET_RAW(self, QUEUE_CLOSED);

            wakeup_all(&queue_ptr(self)->waitq);
        }

        return self;
      }
    end

    # call-seq: closed?
    #
    # Returns +true+ if the queue is closed.
    def closed?
      Primitive.cexpr!('RBOOL(FL_TEST_RAW(self, QUEUE_CLOSED))')
    end

    # call-seq:
    #   length
    #   size
    #
    # Returns the length of the queue.
    def length
      Primitive.cexpr!('LONG2NUM(queue_ptr(self)->len)')
    end
    alias_method :size, :length

    # call-seq: empty?
    #
    # Returns +true+ if the queue is empty.
    def empty?
      Primitive.cexpr!('RBOOL(queue_ptr(self)->len == 0)')
    end

    # Removes all objects from the queue.
    def clear
      Primitive.cstmt! %{
        queue_clear(queue_ptr(self));
        return self;
      }
    end

    # call-seq:
    #   num_waiting
    #
    # Returns the number of threads waiting on the queue.
    def num_waiting
      Primitive.cexpr!('INT2NUM(queue_ptr(self)->num_waiting)')
    end

    def marshal_dump # :nodoc:
      raise TypeError, "can't dump #{self.class}"
    end

    # call-seq:
    #   freeze
    #
    # The queue can't be frozen, so this method raises an exception:
    #   Thread::Queue.new.freeze # Raises TypeError (cannot freeze #<Thread::Queue:0x...>)
    def freeze
      raise TypeError, "cannot freeze #{self}"
    end
  end

  # This class represents queues of specified size capacity.  The push operation
  # may be blocked if the capacity is full.
  #
  # See Thread::Queue for an example of how a Thread::SizedQueue works.
  class SizedQueue < Queue
    # Document-method: SizedQueue::new
    # call-seq: new(max)
    #
    # Creates a fixed-length queue with a maximum size of +max+.
    def initialize(vmax)
      Primitive.szqueue_initialize(vmax)
    end

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

    # call-seq:
    #   close
    #
    # Similar to Thread::Queue#close.
    #
    # The difference is behavior with waiting enqueuing threads.
    #
    # If there are waiting enqueuing threads, they are interrupted by
    # raising ClosedQueueError('queue closed').
    def close
      Primitive.cstmt! %{
        if (!queue_closed_p(self)) {
            struct rb_szqueue *sq = szqueue_ptr(self);

            FL_SET(self, QUEUE_CLOSED);
            wakeup_all(szqueue_waitq(sq));
            wakeup_all(szqueue_pushq(sq));
        }
        return self;
      }
    end

    # Removes all objects from the queue.
    def clear
      Primitive.cstmt! %{
        struct rb_szqueue *sq = szqueue_ptr(self);
        queue_clear(&sq->q);
        wakeup_all(szqueue_pushq(sq));
        return self;
      }
    end

    # Returns the number of threads waiting on the queue.
    def num_waiting
      Primitive.cstmt! %{
        struct rb_szqueue *sq = szqueue_ptr(self);
        return INT2NUM(sq->q.num_waiting + sq->num_waiting_push);
      }
    end

    # Returns the maximum size of the queue.
    def max
      Primitive.cexpr!('LONG2NUM(szqueue_ptr(self)->max)')
    end

    # call-seq: max=(number)
    #
    # Sets the maximum size of the queue to the given +number+.
    def max=(vmax)
      Primitive.cstmt! %{
        long max = NUM2LONG(vmax);
        if (max <= 0) {
            rb_raise(rb_eArgError, "queue size must be positive");
        }

        long diff = 0;
        struct rb_szqueue *sq = szqueue_ptr(self);

        if (max > sq->max) {
            diff = max - sq->max;
        }
        sq->max = max;
        sync_wakeup(szqueue_pushq(sq), diff);
        return vmax;
      }
    end
  end

  #  Thread::Mutex implements a simple semaphore that can be used to
  #  coordinate access to shared data from multiple concurrent threads.
  #
  #  Example:
  #
  #    semaphore = Thread::Mutex.new
  #
  #    a = Thread.new {
  #      semaphore.synchronize {
  #        # access shared resource
  #      }
  #    }
  #
  #    b = Thread.new {
  #      semaphore.synchronize {
  #        # access shared resource
  #      }
  #    }
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

  #  ConditionVariable objects augment class Mutex. Using condition variables,
  #  it is possible to suspend while in the middle of a critical section until a
  #  condition is met, such as a resource becomes available.
  #
  #  Due to non-deterministic scheduling and spurious wake-ups, users of
  #  condition variables should always use a separate boolean predicate (such as
  #  reading from a boolean variable) to check if the condition is actually met
  #  before starting to wait, and should wait in a loop, re-checking the
  #  condition every time the ConditionVariable is waken up.  The idiomatic way
  #  of using condition variables is calling the +wait+ method in an +until+
  #  loop with the predicate as the loop condition.
  #
  #    condvar.wait(mutex) until condition_is_met
  #
  #  In the example below, we use the boolean variable +resource_available+
  #  (which is protected by +mutex+) to indicate the availability of the
  #  resource, and use +condvar+ to wait for that variable to become true.  Note
  #  that:
  #
  #  1.  Thread +b+ may be scheduled before thread +a1+ and +a2+, and may run so
  #      fast that it have already made the resource available before either
  #      +a1+ or +a2+ starts. Therefore, +a1+ and +a2+ should check if
  #      +resource_available+ is already true before starting to wait.
  #  2.  The +wait+ method may spuriously wake up without signalling. Therefore,
  #      thread +a1+ and +a2+ should recheck +resource_available+ after the
  #      +wait+ method returns, and go back to wait if the condition is not
  #      actually met.
  #  3.  It is possible that thread +a2+ starts right after thread +a1+ is waken
  #      up by +b+.  Thread +a2+ may have acquired the +mutex+ and consumed the
  #      resource before thread +a1+ acquires the +mutex+.  This necessitates
  #      rechecking after +wait+, too.
  #
  #  Example:
  #
  #    mutex = Thread::Mutex.new
  #
  #    resource_available = false
  #    condvar = Thread::ConditionVariable.new
  #
  #    a1 = Thread.new {
  #      # Thread 'a1' waits for the resource to become available and consumes
  #      # the resource.
  #      mutex.synchronize {
  #        condvar.wait(mutex) until resource_available
  #        # After the loop, 'resource_available' is guaranteed to be true.
  #
  #        resource_available = false
  #        puts "a1 consumed the resource"
  #      }
  #    }
  #
  #    a2 = Thread.new {
  #      # Thread 'a2' behaves like 'a1'.
  #      mutex.synchronize {
  #        condvar.wait(mutex) until resource_available
  #        resource_available = false
  #        puts "a2 consumed the resource"
  #      }
  #    }
  #
  #    b = Thread.new {
  #      # Thread 'b' periodically makes the resource available.
  #      loop {
  #        mutex.synchronize {
  #          resource_available = true
  #
  #          # Notify one waiting thread if any.  It is possible that neither
  #          # 'a1' nor 'a2 is waiting on 'condvar' at this moment.  That's OK.
  #          condvar.signal
  #        }
  #        sleep 1
  #      }
  #    }
  #
  #    # Eventually both 'a1' and 'a2' will have their resources, albeit in an
  #    # unspecified order.
  #    [a1, a2].each {|th| th.join}
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

Mutex = Thread::Mutex
ConditionVariable = Thread::ConditionVariable
Queue = Thread::Queue
SizedQueue = Thread::SizedQueue
