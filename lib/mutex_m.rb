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
#	extended object can be handled like Mutex
#

module Mutex_m
  def Mutex_m.append_features(cl)
    super
    unless cl.instance_of?(Module)
      cl.module_eval %q{
	alias locked? mu_locked?
	alias lock mu_lock
	alias unlock mu_unlock
	alias try_lock mu_try_lock
	alias synchronize mu_synchronize
      }
    end
    return self
  end
  
  def Mutex_m.extend_object(obj)
    super
    obj.mu_extended
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
    initialize
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
  
  private
  
  def initialize(*args)
    ret = super
    @mu_waiting = []
    @mu_locked = FALSE;
    return ret
  end
end
