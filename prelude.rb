class Thread
  MUTEX_FOR_THREAD_EXCLUSIVE = Mutex.new # :nodoc:

  # call-seq:
  #    Thread.exclusive { block }   => obj
  #
  # Wraps the block in a single, VM-global Mutex.synchronize, returning the
  # value of the block. A thread executing inside the exclusive section will
  # only block other threads which also use the Thread.exclusive mechanism.
  def self.exclusive
    MUTEX_FOR_THREAD_EXCLUSIVE.synchronize{
      yield
    }
  end
end
