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
    # returned.
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
    # returned.
    def pop(non_block = false, timeout: nil)
      if non_block && timeout
        raise ArgumentError, "can't set a timeout if non_block is enabled"
      end
      Primitive.rb_szqueue_pop(non_block, timeout)
    end
    alias_method :deq, :pop
    alias_method :shift, :pop
  end
end
