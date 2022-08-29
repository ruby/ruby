class Thread
  class Queue
    # call-seq:
    #   pop(non_block=false, timeout: nil, exception: true)
    #
    # Retrieves data from the queue.
    #
    # If the queue is empty, the calling thread is suspended until data
    # is pushed onto the queue.
    #
    # If the queue is both empty and closed, +nil+ is returned.
    #
    # If the queue is empty and +non_block+ is true, the thread isn't
    # suspended, and +ThreadError+ is raised.
    #
    # If +exception+ is +false+, instead of raising +ThreadError+
    # +nil+ is returned.
    #
    # If +timeout+ seconds have passed and no data is available,
    # +nil+ is returned.
    def pop(non_block = false, timeout: nil, exception: true)
      if non_block && timeout
        raise ArgumentError, "can't set a timeout if non_block is enabled"
      end
      Primitive.rb_queue_pop(non_block, timeout, exception)
    end
    alias_method :deq, :pop
    alias_method :shift, :pop

    # call-seq:
    #   push(object, exception: true)
    #
    # Pushes the given +object+ to the queue.
    #
    # If the queue is closed, +ClosedQueueError+ is raised.
    #
    # If +exception+ is +false+, instead of raising +ClosedQueueError+,
    # +nil+ is returned.
    def push(object, exception: true)
      Primitive.rb_queue_push(object, exception)
    end
    alias_method :enq, :push
    alias_method :<<, :push
  end

  class SizedQueue
    # call-seq:
    #   pop(non_block=false, timeout: nil, exception: true)
    #
    # Retrieves data from the queue.
    #
    # If the queue is empty, the calling thread is suspended until data
    # is pushed onto the queue.
    #
    # If the queue is both empty and closed, +nil+ is returned.
    #
    # If the queue is empty and +non_block+ is true, the thread isn't
    # suspended, and +ThreadError+ is raised. If +exception+
    #
    # If +exception+ is +false+, instead of raising +ThreadError+
    # +nil+ is returned.
    #
    # If +timeout+ seconds have passed and no data is available +nil+ is
    # returned.
    def pop(non_block = false, timeout: nil, exception: true)
      if non_block && timeout
        raise ArgumentError, "can't set a timeout if non_block is enabled"
      end
      Primitive.rb_szqueue_pop(non_block, timeout, exception)
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
    # If there is no space left in the queue, the thread is suspended
    # until space becomes available, unless +non_block+ is true.
    #
    # If +non_block+ is true, the
    # thread isn't suspended, and +ThreadError+ is raised.
    #
    # If the queue is closed, +ClosedQueueError+ is raised.
    #
    # If +exception+ is +false+, instead of raising +ClosedQueueError+ or
    # +ThreadError+, +nil+ is returned.
    #
    # If +timeout+ seconds have passed and no space is available +nil+ is
    # returned.
    #
    # Otherwise it returns +self+.
    def push(object, non_block = false, timeout: nil, exception: true)
      if non_block && timeout
        raise ArgumentError, "can't set a timeout if non_block is enabled"
      end
      Primitive.rb_szqueue_push(object, non_block, timeout, exception)
    end
    alias_method :enq, :push
    alias_method :<<, :push
  end
end
