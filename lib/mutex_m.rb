#
#   mutex_m.rb - 
#   	$Release Version: 2.0$
#   	$Revision: 1.7 $
#   	$Date: 1998/02/27 04:28:57 $
#       Original from mutex.rb
#   	by Keiju ISHITSUKA(SHL Japan Inc.)
#
# --
#   Usage:
#	require "mutex_m.rb"
#	obj = Object.new
#	obj.extend Mutex_m
#	...
#	後はMutexと同じ使い方
#

require "finalize"

module Mutex_m
  def Mutex_m.extendable_module(obj)
    if Fixnum === obj or TRUE === obj or FALSE === obj or nil == obj
      raise TypeError, "Mutex_m can't extend to this class(#{obj.type})"
    else
      begin
	obj.instance_eval "@mu_locked"
	For_general_object
      rescue TypeError
	For_primitive_object
      end
    end
  end
  
  def Mutex_m.includable_module(cl)
    begin
      dummy = cl.new
      Mutex_m.extendable_module(dummy)
    rescue NameError
      # newが定義されていない時は, DATAとみなす.
      For_primitive_object
    end
  end

  def Mutex_m.extend_class(cl)
    return super if cl.instance_of?(Module)
    
    # モジュールの時は何もしない. クラスの場合, 適切なモジュールの決定
    # とaliasを行う.  
    real = includable_module(cl)
    cl.module_eval %q{
      include real

      alias locked? mu_locked?
      alias lock mu_lock
      alias unlock mu_unlock
      alias try_lock mu_try_lock
      alias synchronize mu_synchronize
    }
  end
  
  def Mutex_m.extend_object(obj)
    obj.extend(Mutex_m.extendable_module(obj))
  end

  def mu_extended
    unless (defined? locked? and
	    defined? lock and
	    defined? unlock and
	    defined? try_lock and
	    defined? synchronize)
      eval "class << self
	alias locked? mu_locked?
	alias lock mu_lock
	alias unlock mu_unlock
	alias try_lock mu_try_lock
	alias synchronize mu_synchronize
      end"
    end
  end
  
  # locking 
  def mu_synchronize
    begin
      mu_lock
      yield
    ensure
      mu_unlock
    end
  end
  
  # internal class
  module For_general_object
    include Mutex_m
    
    def For_general_object.extend_object(obj)
      super
      obj.mu_extended
    end
    
    def mu_extended
      super
      @mu_waiting = []
      @mu_locked = FALSE;
    end

    def mu_locked?
      @mu_locked
    end

    def mu_try_lock
      result = FALSE
      Thread.critical = TRUE
      unless @mu_locked
	@mu_locked = TRUE
	result = TRUE
      end
      Thread.critical = FALSE
      result
    end

    def mu_lock
      while (Thread.critical = TRUE; @mu_locked)
	@mu_waiting.push Thread.current
	Thread.stop
      end
      @mu_locked = TRUE
      Thread.critical = FALSE
      self
    end

    def mu_unlock
      return unless @mu_locked
      Thread.critical = TRUE
      wait = @mu_waiting
      @mu_waiting = []
      @mu_locked = FALSE
      Thread.critical = FALSE
      for w in wait
	w.run
      end
      self
    end

  end

  module For_primitive_object
    include Mutex_m
    Mu_Locked = Hash.new
    
    def For_primitive_object.extend_object(obj)
      super

      obj.mu_extended
      Finalizer.add(obj, For_primitive_object, :mu_finalize)
    end
    
    def mu_extended
      super
      initialize
    end
    
    def For_primitive_object.mu_finalize(id)
      Thread.critical = TRUE
      if wait = Mu_Locked.delete(id)
	# wait == [] ときだけ GCされるので, for w in wait は意味なし.
	Thread.critical = FALSE
	for w in wait
	  w.run
	end
      else
	Thread.critical = FALSE
      end
      self
    end
    
    def mu_locked?
      Mu_Locked.key?(self.id)
    end

    def mu_try_lock
      Thread.critical = TRUE
      if Mu_Locked.key?(self.id)
	ret = FALSE
      else
	Mu_Locked[self.id] = []
	Finalizer.add(self, For_primitive_object, :mu_finalize)
	ret = TRUE
      end
      Thread.critical = FALSE
      ret
    end

    def mu_lock
      while (Thread.critical = TRUE; w = Mu_Locked[self.id])
	w.push Thread.current
	Thread.stop
      end
      Mu_Locked[self.id] = []
      Finalizer.add(self, For_primitive_object, :mu_finalize)
      Thread.critical = FALSE
      self
    end

    def mu_unlock
      Thread.critical = TRUE
      if wait = Mu_Locked.delete(self.id)
	Finalizer.delete(self, For_primitive_object, :mu_finalize)
	Thread.critical = FALSE
	for w in wait
	  w.run
	end
      else
	Thread.critical = FALSE
      end
      self
    end
  end
end

