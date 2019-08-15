class TimerAction
  def register
    MSpec.register :start, self
    MSpec.register :finish, self
  end

  def start
    @start = Time.now
  end

  def finish
    @stop = Time.now
  end

  def elapsed
    @stop - @start
  end

  def format
    "Finished in %f seconds" % elapsed
  end
end
