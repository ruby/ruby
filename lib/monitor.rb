## monitor.rb

# Author: Shugo Maeda <shugo@po.aianet.ne.jp>
# Version: $Revision: 0.1 $

# USAGE:
#
#   foo = Foo.new
#   foo.extend(MonitorMixin)
#   cond = foo.new_cond
#
#   thread1:
#   foo.synchronize {
#     ...
#     cond.wait_until { foo.done? }
#     ...
#   }
#
#   thread2:
#   foo.synchronize {
#     foo.do_something
#     cond.signal
#   }

# ATTENTION:
#
#   If you include MonitorMixin and override `initialize', you should
#   call `super'.
#   If you include MonitorMixin to built-in classes, you should override
#   `new' to call `mon_initialize'.

## Code:
  
require "final"

module MonitorMixin
  
  RCS_ID = %q$Id: monitor.rb,v 0.1 1998/03/01 08:40:18 shugo Exp shugo $
  
  module Primitive
    
    include MonitorMixin
    
    MON_OWNER_TABLE = {}
    MON_COUNT_TABLE = {}
    MON_ENTERING_QUEUE_TABLE = {}
    MON_WAITING_QUEUE_TABLE = {}
    
    FINALIZER = Proc.new { |id|
      MON_OWNER_TABLE.delete(id)
      MON_COUNT_TABLE.delete(id)
      MON_ENTERING_QUEUE_TABLE.delete(id)
      MON_WAITING_QUEUE_TABLE.delete(id)
    }
  
    def self.extend_object(obj)
      super(obj)
      obj.mon_initialize
    end
    
    def mon_initialize
      MON_OWNER_TABLE[id] = nil
      MON_COUNT_TABLE[id] = 0
      MON_ENTERING_QUEUE_TABLE[id] = []
      MON_WAITING_QUEUE_TABLE[id] = []
      ObjectSpace.define_finalizer(self, FINALIZER)
    end
    
    def mon_owner
      return MON_OWNER_TABLE[id]
    end
    
    def mon_count
      return MON_COUNT_TABLE[id]
    end
    
    def mon_entering_queue
      return MON_ENTERING_QUEUE_TABLE[id]
    end
    
    def mon_waiting_queue
      return MON_WAITING_QUEUE_TABLE[id]
    end
    
    def set_mon_owner(val)
      return MON_OWNER_TABLE[id] = val
    end
    
    def set_mon_count(val)
      return MON_COUNT_TABLE[id] = val
    end
    
    private :mon_count, :mon_entering_queue, :mon_waiting_queue,
      :set_mon_owner, :set_mon_count
  end
  
  module NonPrimitive
    
    include MonitorMixin
      
    attr_reader :mon_owner, :mon_count,
      :mon_entering_queue, :mon_waiting_queue
  
    def self.extend_object(obj)
      super(obj)
      obj.mon_initialize
    end
  
    def mon_initialize
      @mon_owner = nil
      @mon_count = 0
      @mon_entering_queue = []
      @mon_waiting_queue = []
    end
    
    def set_mon_owner(val)
      @mon_owner = val
    end
    
    def set_mon_count(val)
      @mon_count = val
    end
    
    private :mon_count, :mon_entering_queue, :mon_waiting_queue,
      :set_mon_owner, :set_mon_count
  end
  
  def self.extendable_module(obj)
    if Fixnum === obj or TrueClass === obj or FalseClass === obj or
	NilClass === obj
      raise TypeError, "MonitorMixin can't extend #{obj.type}"
    else
      begin
	obj.instance_eval("@mon_owner")
	return NonPrimitive
      rescue TypeError
	return Primitive
      end
    end
  end
  
  def self.extend_object(obj)
    obj.extend(extendable_module(obj))
  end
  
  def self.includable_module(klass)
    if klass.instance_of?(Module)
      return NonPrimitive
    end
    begin
      dummy = klass.new
      return extendable_module(dummy)
    rescue ArgumentError
      if klass.singleton_methods.include?("new")
	return Primitive
      else
	return NonPrimitive
      end
    rescue NameError
      raise TypeError, "#{klass} can't include MonitorMixin"
    end
  end
  
  def self.append_features(klass)
    mod = includable_module(klass)
    klass.module_eval("include mod")
  end
  
  def initialize(*args)
    super
    mon_initialize
  end
  
  def try_mon_enter
    result = false
    Thread.critical = true
    if mon_owner.nil?
      set_mon_owner(Thread.current)
    end
    if mon_owner == Thread.current
      set_mon_count(mon_count + 1)
      result = true
    end
    Thread.critical = false
    return result
  end

  def mon_enter
    Thread.critical = true
    while mon_owner != nil && mon_owner != Thread.current
      mon_entering_queue.push(Thread.current)
      Thread.stop
      Thread.critical = true
    end
    set_mon_owner(Thread.current)
    set_mon_count(mon_count + 1)
    Thread.critical = false
  end
  
  def mon_exit
    if mon_owner != Thread.current
      raise ThreadError, "current thread not owner"
    end
    Thread.critical = true
    set_mon_count(mon_count - 1)
    if mon_count == 0
      set_mon_owner(nil)
      if mon_waiting_queue.empty?
	t = mon_entering_queue.shift
      else
	t = mon_waiting_queue.shift
      end
    end
    t.wakeup if t
    Thread.critical = false
    Thread.pass
  end

  def mon_synchronize
    mon_enter
    begin
      yield
    ensure
      mon_exit
    end
  end
  alias synchronize mon_synchronize

  class ConditionVariable
    def initialize(monitor)
      @monitor = monitor
      @waiters = []
    end
    
    def wait
      if @monitor.mon_owner != Thread.current
	raise ThreadError, "current thread not owner"
      end
      
      @monitor.instance_eval(<<MON_EXIT)
      Thread.critical = true
      _count = mon_count
      set_mon_count(0)
      set_mon_owner(nil)
      if mon_waiting_queue.empty?
	t = mon_entering_queue.shift
      else
	t = mon_waiting_queue.shift
      end
      t.wakeup if t
      Thread.critical = false
MON_EXIT
      
      Thread.critical = true
      @waiters.push(Thread.current)
      Thread.stop
      
      @monitor.instance_eval(<<MON_ENTER)
      Thread.critical = true
      while mon_owner != nil && mon_owner != Thread.current
	mon_waiting_queue.push(Thread.current)
	Thread.stop
	Thread.critical = true
      end
      set_mon_owner(Thread.current)
      set_mon_count(_count)
      Thread.critical = false
MON_ENTER
    end
    
    def wait_while
      while yield
	wait
      end
    end
    
    def wait_until
      until yield
	wait
      end
    end
    
    def signal
      if @monitor.mon_owner != Thread.current
	raise ThreadError, "current thread not owner"
      end
      Thread.critical = true
      t = @waiters.shift
      t.wakeup if t
      Thread.critical = false
      Thread.pass
    end
    
    def broadcast
      if @monitor.mon_owner != Thread.current
	raise ThreadError, "current thread not owner"
      end
      Thread.critical = true
      for t in @waiters
	t.wakeup
      end
      @waiters.clear
      Thread.critical = false
      Thread.pass
    end
    
    def count_waiters
      return @waiters.length
    end
  end
  
  def new_cond
    return ConditionVariable.new(self)
  end
end

class Monitor
  include MonitorMixin
  alias try_enter try_mon_enter
  alias enter mon_enter
  alias exit mon_exit
  alias owner mon_owner
end

## monitor.rb ends here
