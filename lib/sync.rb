#
#   sync.rb - ���������2-�ե�������å����饹
#   	$Release Version: 0.1$
#   	$Revision$
#   	$Date$
#   	by Keiju ISHITSUKA
#
# --
#  Usage:
#   Sync_m, Synchronizer_m
#
#   Sync_m#sync_mode
#   Sync_m#sync_locked?, locked?
#   Sync_m#sync_shared?, shared?
#   Sync_m#sync_exclusive?, sync_exclusive?
#   Sync_m#sync_try_lock, try_lock
#   Sync_m#sync_lock, lock
#   Sync_m#sync_unlock, unlock
#
#   Sync, Synchronicer:
#	include Sync_m
#
#   sync = Sync.new
#   Sync#mode
#   Sync#locked?
#   Sync#shared?
#   Sync#exclusive?
#   Sync#try_lock(mode) -- mode = :EX, :SH, :UN
#   Sync#lock(mode)     -- mode = :EX, :SH, :UN
#   Sync#unlock
#   Sync#synchronize(mode) {...}
#   
#

unless defined? Thread
  fail "Thread not available for this ruby interpreter"
end

require "finalize.rb"

module Sync_m
  RCS_ID='-$Header$-'
  
  UN = :UN
  SH = :SH
  EX = :EX
  
  class Err < Exception
    def Err.Fail(*opt)
      fail self, sprintf(self::Message, *opt)
    end
    
    class UnknownLocker < Err
      Message = "Thread(%s) not locked."
      def UnknownLocker.Fail(th)
	super(th.inspect)
      end
    end
    
    class LockModeFailer < Err
      Message = "Unknown lock mode(%s)"
      def LockModeFailer.Fail(mode)
	if mode.id2name
	  mode = id2name
	end
	super(mode)
      end
    end
  end
  
  def Sync_m.extend_object(obj)
    if Fixnum === obj or TRUE === obj or FALSE === obj or nil == obj
      raise TypeError, "Sync_m can't extend to this class(#{obj.type})"
    else
      begin
	eval "class << obj
		@sync_locked
	      end"
	obj.extend(For_primitive_object)
      rescue TypeError
	obj.extend(For_general_object)
      end
    end
  end
  
  def sync_extended
    unless (defined? locked? and
	    defined? shared? and
	    defined? exclusive? and
	    defined? lock and
	    defined? unlock and
	    defined? try_lock and
	    defined? synchronize)
      eval "class << self
	alias locked? sync_locked?
        alias shared? sync_shared?
        alias excluive? sync_exclusive?
	alias lock sync_lock
	alias unlock sync_unlock
	alias try_lock sync_try_lock
	alias synchronize sync_synchronize
      end"
    end
  end
  
  def sync_locked?
    sync_mode != UN
  end
  
  def sync_shared?
    sync_mode == SH
  end
  
  def sync_exclusive?
    sync_mode == EX
  end
  
  def sync_try_lock(mode = EX)
    return unlock if sync_mode == UN
    
    Thread.critical = TRUE
    ret = sync_try_lock_sub(sync_mode)
    Thread.critical = FALSE
    ret
  end
  
  def sync_lock(m = EX)
    return unlock if m == UN

    until (Thread.critical = TRUE; sync_try_lock_sub(m))
      if sync_sh_locker[Thread.current]
	sync_upgrade_waiting.push [Thread.current, sync_sh_locker[Thread.current]]
	sync_sh_locker.delete(Thread.current)
      else
	sync_waiting.push Thread.current
      end
      Thread.stop
    end
    Thread.critical = FALSE
    self
  end
  
  def sync_unlock(m = EX)
    Thread.critical = TRUE
    if sync_mode == UN
      Thread.critical = FALSE
      Err::UnknownLocker.Fail(Thread.current)
    end
    
    m = sync_mode if m == EX and sync_mode == SH
    
    runnable = FALSE
    case m
    when UN
      Thread.critical = FALSE
      Err::UnknownLocker.Fail(Thread.current)
      
    when EX
      if sync_ex_locker == Thread.current
	if (self.sync_ex_count = sync_ex_count - 1) == 0
	  self.sync_ex_locker = nil
	  if sync_sh_locker.include?(Thread.current)
	    self.sync_mode = SH
	  else
	    self.sync_mode = UN
	  end
	  runnable = TRUE
	end
      else
	Err::UnknownLocker.Fail(Thread.current)
      end
      
    when SH
      if (count = sync_sh_locker[Thread.current]).nil?
	Err::UnknownLocker.Fail(Thread.current)
      else
	if (sync_sh_locker[Thread.current] = count - 1) == 0 
	  sync_sh_locker.delete(Thread.current)
	  if sync_sh_locker.empty? and sync_ex_count == 0
	    self.sync_mode = UN
	    runnable = TRUE
	  end
	end
      end
    end
    
    if runnable
      if sync_upgrade_waiting.size > 0
	for k, v in sync_upgrade_waiting
	  sync_sh_locker[k] = v
	end
	wait = sync_upgrade_waiting
	self.sync_upgrade_waiting = []
	Thread.critical = FALSE
	
	for w, v in wait
	  w.run
	end
      else
	wait = sync_waiting
	self.sync_waiting = []
	Thread.critical = FALSE
	for w in wait
	  w.run
	end
      end
    end
    
    Thread.critical = FALSE
    self
  end
  
  def sync_try_lock_sub(m)
    case m
    when SH
      case sync_mode
      when UN
	self.sync_mode = m
	sync_sh_locker[Thread.current] = 1
	ret = TRUE
      when SH
	count = 0 unless count = sync_sh_locker[Thread.current]
	sync_sh_locker[Thread.current] = count + 1
	ret = TRUE
      when EX
	# ����, �⡼�ɤ�EX�Ǥ������, ɬ��EX��å��Ȥʤ�.
	if sync_ex_locker == Thread.current
	  self.sync_ex_count = sync_ex_count + 1
	  ret = TRUE
	else
	  ret = FALSE
	end
      end
    when EX
      if sync_mode == UN or
	sync_mode == SH && sync_sh_locker.size == 1 && sync_sh_locker.include?(Thread.current) 
	self.sync_mode = m
	self.sync_ex_locker = Thread.current
	self.sync_ex_count = 1
	ret = TRUE
	
      elsif sync_mode == EX && sync_ex_locker == Thread.current
	self.sync_ex_count = sync_ex_count + 1
	ret = TRUE
      else
	ret = FALSE
      end
    else
      Thread.critical = FALSE
      Err::LockModeFailer.Fail mode
    end
    return ret
  end
  private :sync_try_lock_sub
  
  def sync_synchronize(mode = EX)
    begin
      sync_lock(mode)
      yield
    ensure
      sync_unlock
    end
  end
  
  module For_primitive_object
    include Sync_m
    
    LockState = Struct.new("LockState",
			   :mode,
			   :waiting,
			   :upgrade_waiting,
			   :sh_locker,
			   :ex_locker,
			   :ex_count)
    
    Sync_Locked = Hash.new
    
    def For_primitive_object.extend_object(obj)
      super
      obj.sync_extended
      Finalizer.add(obj, For_primitive_object, :sync_finalize)
    end
    
    def sync_extended
      super
      Sync_Locked[id] = LockState.new(UN, [], [], Hash.new, nil, 0 )
    end
    
    def sync_finalize
      wait = Sync_Locked.delete(id)
      # waiting == [] �Ȥ����� GC�����Τ�, �Ԥ�����β����ϰ�̣���ʤ�.
    end
    
    def sync_mode
      Sync_Locked[id].mode
    end
    def sync_mode=(value)
      Sync_Locked[id].mode = value
    end

    def sync_waiting
      Sync_Locked[id].waiting
    end
    def sync_waiting=(v)
      Sync_Locked[id].waiting = v
    end
    
    def sync_upgrade_waiting
      Sync_Locked[id].upgrade_waiting
    end
    def sync_upgrade_waiting=(v)
      Sync_Locked[id].upgrade_waiting = v
    end
    
    def sync_sh_locker
      Sync_Locked[id].sh_locker
    end
    def sync_sh_locker=(v)
      Sync_Locked[id].sh_locker = v
    end
    
    def sync_ex_locker
      Sync_Locked[id].ex_locker
    end
    def sync_ex_locker=(value)
      Sync_Locked[id].ex_locker = value
    end
    
    def sync_ex_count
      Sync_Locked[id].ex_count
    end
    def sync_ex_count=(value)
      Sync_Locked[id].ex_count = value
    end
    
  end
  
  module For_general_object
    include Sync_m
    
    def For_general_object.extend_object(obj)
      super
      obj.sync_extended
    end
    
    def sync_extended
      super
      @sync_mode = UN
      @sync_waiting = []
      @sync_upgrade_waiting = []
      @sync_sh_locker = Hash.new
      @sync_ex_locker = nil
      @sync_ex_count = 0
    end
    
    attr :sync_mode, TRUE
    
    attr :sync_waiting, TRUE
    attr :sync_upgrade_waiting, TRUE
    attr :sync_sh_locker, TRUE
    attr :sync_ex_locker, TRUE
    attr :sync_ex_count, TRUE
    
  end
end
Synchronizer_m = Sync_m

class Sync
  include Sync_m::For_general_object
    
  def initialize
    sync_extended
  end
    
end
Synchronizer = Sync
