#
#		thread.rb - thread support classes
#			$Date$
#			by Yukihiro Matsumoto <matz@caelum.co.jp>
#

unless defined? Thread
  fail "Thread not available for this ruby interpreter"
end

unless defined? ThreadError
  class ThreadError<Exception
  end
end

if $DEBUG
  Thread.abort_on_exception = true
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
    result = FALSE
    Thread.critical = TRUE
    unless @locked
      @locked = TRUE
      result = TRUE
    end
    Thread.critical = FALSE
    result
  end

  def lock
    while (Thread.critical = TRUE; @locked)
      @waiting.push Thread.current
      Thread.stop
    end
    @locked = TRUE
    Thread.critical = FALSE
    self
  end

  def unlock
    return unless @locked
    Thread.critical = TRUE
    wait = @waiting
    @waiting = []
    @locked = FALSE
    Thread.critical = FALSE
    for w in wait
      w.run
    end
    self
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

class Queue
  def initialize
    @que = []
    @waiting = []
  end

  def push(obj)
    Thread.critical = TRUE
    @que.push obj
    t = @waiting.shift
    Thread.critical = FALSE
    t.run if t
  end

  def pop non_block=FALSE
    item = nil
    until item
      Thread.critical = TRUE
      if @que.length == 0
	if non_block
	  Thread.critical = FALSE
	  raise ThreadError, "queue empty"
	end
	@waiting.push Thread.current
	Thread.stop
      else
	item = @que.shift
      end
    end
    Thread.critical = FALSE
    item
  end

  def empty?
    @que.length == 0
  end

  def length
    @que.length
  end
  alias size length
end

class SizedQueue<Queue
  def initialize(max)
    @max = max
    @queue_wait = []
    super()
  end

  def push(obj)
    while @que.length >= @max
      @queue_wait.push Thread.current
      Thread.stop
    end
    super
  end

  def pop(*args)
    if @que.length < @max
      t = @queue_wait.shift
      t.run if t
    end
    pop = super
    pop
  end
end
