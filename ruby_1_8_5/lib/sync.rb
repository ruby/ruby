#
#   sync.rb - 2 phase lock with counter
#   	$Release Version: 1.0$
#   	$Revision: 1.4 $
#   	$Date: 2001/06/06 14:19:33 $
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#
# --
#  Sync_m, Synchronizer_m
#  Usage:
#   obj.extend(Sync_m)
#   or
#   class Foo
#	include Sync_m
#	:
#   end
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
#   Usage:
#   sync = Sync.new
#
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

module Sync_m
  RCS_ID='-$Header: /src/ruby/lib/sync.rb,v 1.4 2001/06/06 14:19:33 keiju Exp $-'
  
  # lock mode
  UN = :UN
  SH = :SH
  EX = :EX
  
  # exceptions
  class Err < StandardError
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
  
  def Sync_m.define_aliases(cl)
    cl.module_eval %q{
      alias locked? sync_locked?
      alias shared? sync_shared?
      alias exclusive? sync_exclusive?
      alias lock sync_lock
      alias unlock sync_unlock
      alias try_lock sync_try_lock
      alias synchronize sync_synchronize
    }
  end
  
  def Sync_m.append_features(cl)
    super
    unless cl.instance_of?(Module)
      # do nothing for Modules
      # make aliases and include the proper module.
      define_aliases(cl)
    end
  end
  
  def Sync_m.extend_object(obj)
    super
    obj.sync_extended
  end

  def sync_extended
    unless (defined? locked? and
	    defined? shared? and
	    defined? exclusive? and
	    defined? lock and
	    defined? unlock and
	    defined? try_lock and
	    defined? synchronize)
      Sync_m.define_aliases(class<<self;self;end)
    end
    sync_initialize
  end

  # accessing
  def sync_locked?
    sync_mode != UN
  end
  
  def sync_shared?
    sync_mode == SH
  end
  
  def sync_exclusive?
    sync_mode == EX
  end
  
  # locking methods.
  def sync_try_lock(mode = EX)
    return unlock if sync_mode == UN
    
    Thread.critical = true
    ret = sync_try_lock_sub(sync_mode)
    Thread.critical = false
    ret
  end
  
  def sync_lock(m = EX)
    return unlock if m == UN

    until (Thread.critical = true; sync_try_lock_sub(m))
      if sync_sh_locker[Thread.current]
	sync_upgrade_waiting.push [Thread.current, sync_sh_locker[Thread.current]]
	sync_sh_locker.delete(Thread.current)
      else
	sync_waiting.push Thread.current
      end
      Thread.stop
    end
    Thread.critical = false
    self
  end
  
  def sync_unlock(m = EX)
    Thread.critical = true
    if sync_mode == UN
      Thread.critical = false
      Err::UnknownLocker.Fail(Thread.current)
    end
    
    m = sync_mode if m == EX and sync_mode == SH
    
    runnable = false
    case m
    when UN
      Thread.critical = false
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
	  runnable = true
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
	    runnable = true
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
	Thread.critical = false
	
	for w, v in wait
	  w.run
	end
      else
	wait = sync_waiting
	self.sync_waiting = []
	Thread.critical = false
	for w in wait
	  w.run
	end
      end
    end
    
    Thread.critical = false
    self
  end
  
  def sync_synchronize(mode = EX)
    begin
      sync_lock(mode)
      yield
    ensure
      sync_unlock
    end
  end

  attr :sync_mode, true
    
  attr :sync_waiting, true
  attr :sync_upgrade_waiting, true
  attr :sync_sh_locker, true
  attr :sync_ex_locker, true
  attr :sync_ex_count, true
    
  private

  def sync_initialize
    @sync_mode = UN
    @sync_waiting = []
    @sync_upgrade_waiting = []
    @sync_sh_locker = Hash.new
    @sync_ex_locker = nil
    @sync_ex_count = 0
  end

  def initialize(*args)
    sync_initialize
    super
  end
    
  def sync_try_lock_sub(m)
    case m
    when SH
      case sync_mode
      when UN
	self.sync_mode = m
	sync_sh_locker[Thread.current] = 1
	ret = true
      when SH
	count = 0 unless count = sync_sh_locker[Thread.current]
	sync_sh_locker[Thread.current] = count + 1
	ret = true
      when EX
	# in EX mode, lock will upgrade to EX lock
	if sync_ex_locker == Thread.current
	  self.sync_ex_count = sync_ex_count + 1
	  ret = true
	else
	  ret = false
	end
      end
    when EX
      if sync_mode == UN or
	sync_mode == SH && sync_sh_locker.size == 1 && sync_sh_locker.include?(Thread.current) 
	self.sync_mode = m
	self.sync_ex_locker = Thread.current
	self.sync_ex_count = 1
	ret = true
      elsif sync_mode == EX && sync_ex_locker == Thread.current
	self.sync_ex_count = sync_ex_count + 1
	ret = true
      else
	ret = false
      end
    else
      Thread.critical = false
      Err::LockModeFailer.Fail mode
    end
    return ret
  end
end
Synchronizer_m = Sync_m

class Sync
  #Sync_m.extend_class self
  include Sync_m
    
  def initialize
    super
  end
    
end
Synchronizer = Sync
