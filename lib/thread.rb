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
    @locked = false;
  end

  def locked?
    @locked
  end

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

  def lock
    while (Thread.critical = true; @locked)
      @waiting.push Thread.current
      Thread.stop
    end
    @locked = true
    Thread.critical = false
    self
  end

  def unlock
    return unless @locked
    Thread.critical = true
    wait = @waiting
    @waiting = []
    @locked = false
    Thread.critical = false
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

  def num_waiting
    @waiting.size
  end
end

class Queue
  def initialize
    @que = []
    @waiting = []
  end

  def push(obj)
    Thread.critical = true
    @que.push obj
    t = @waiting.shift
    Thread.critical = false
    t.run if t
  end

  def pop non_block=false
    item = nil
    until item
      Thread.critical = true
      if @que.length == 0
	if non_block
	  Thread.critical = false
	  raise ThreadError, "queue empty"
	end
	@waiting.push Thread.current
	Thread.stop
      else
	item = @que.shift
      end
    end
    Thread.critical = false
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

  def max
    @max
  end

  def max=(max)
    if @max >= max
      @max = max
    else
      Thread.critical = TRUE
      diff = max - @max
      @max = max
      diff.times do
	t = @queue_wait.shift
	t.run if t
      end
      Thread.critical = FALSE
      @max
    end
  end

  def push(obj)
    Thread.critical = true
    while @que.length >= @max
      @queue_wait.push Thread.current
      Thread.stop
    end
    super
  end

  def pop(*args)
    Thread.critical = true
    if @que.length < @max
      t = @queue_wait.shift
      t.run if t
    end
    pop = super
    pop
  end

  def num_waiting
    @waiting.size + @queue_wait.size
  end
end
