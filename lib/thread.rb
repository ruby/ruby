#
#		thread.rb - thread support classes
#			$Date: 1996/05/21 09:29:21 $
#			by Yukihiro Matsumoto <matz@caelum.co.jp>
#

unless defined? Thread
  fail "Thread not available for this ruby interpreter"
end

unless defined? ThreadError
  class ThreadError<Exception
  end
end

class Mutex
  def initialize
    @waiting = []
    @locked = FALSE;
  end

  def locked?
    @locked
  end

  def try_lock
    Thread.exclusive do
      if not @locked
	@locked=TRUE
	return TRUE
      end
    end
    FALSE
  end

  def lock
    while not try_lock
      @waiting.push Thread.current
      Thread.stop
    end
  end

  def unlock
    @locked = FALSE
    if w = @waiting.shift
      w.run
    end
  end

  def synchronize
    begin
      lock
      yield
    ensure
      unlock
    end
  end
end

class SharedMutex<Mutex
  def initialize
    @locking = nil
    @num_locks = 0;
    super
  end
  def try_lock
    if @locking == Thread.current
      @num_locks += 1
      return TRUE
    end
    if super
      @num_locks = 1
      @locking = Thread.current
      TRUE
    else
      FALSE
    end
  end
  def unlock
    unless @locking == Thread.current
      raise ThreadError, "cannot release shared mutex"
    end
    @num_locks -= 1
    if @num_locks == 0
      @locking = nil
      super
    end
  end
end

class Queue
  def initialize
    @que = []
    @waiting = []
  end

  def push(obj)
    @que.push obj
    if t = @waiting.shift
      t.run
    end
  end

  def pop non_block=FALSE
    if @que.length == 0
      raise ThreadError, "queue empty" if non_block
      @waiting.push Thread.current
      Thread.stop
    end
    @que.shift
  end

  def empty?
    @que.length == 0
  end

  def length
    @que.length
  end
end

class Condition
  def initialize
    @waiting = []
  end

  def wait(mut)
    Thread.exclusive do
      mut.unlock
      @waiting.push Thread.current
    end
    Thread.sleep
    mut.lock
  end

  def signal
    th = nil
    Thread.exclusive do
      th = @waiting.pop
    end
    th.run
  end

  def broadcast
    w = @waiting
    Thread.exclusive do
      th = []
    end
    for th in w
      th.run
    end
  end
end
