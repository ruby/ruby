class Thread
  MUTEX_FOR_THREAD_EXCLUSIVE = Mutex.new # :nodoc:

  # call-seq:
  #    Thread.exclusive { block }   => obj
  #
  # Wraps a block in Thread.critical, restoring the original value
  # upon exit from the critical section, and returns the value of the
  # block.
  def self.exclusive
    MUTEX_FOR_THREAD_EXCLUSIVE.synchronize{
      yield
    }
  end
end
