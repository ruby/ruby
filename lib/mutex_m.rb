#
#   mutex_m.rb - 
#   	$Release Version: 3.0$
#   	$Revision: 1.7 $
#   	$Date: 1998/02/27 04:28:57 $
#       Original from mutex.rb
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       modified by matz
#       patched by akira yamada
#
# --
#   Usage:
#	require "mutex_m.rb"
#	obj = Object.new
#	obj.extend Mutex_m
#	...
#	extended object can be handled like Mutex
#       or
#	class Foo
#	  include Mutex_m
#	  ...
#	end
#	obj = Foo.new
#	this obj can be handled like Mutex
#

module Mutex_m
  def Mutex_m.define_aliases(cl)
    cl.module_eval %q{
      alias locked? mu_locked?
      alias lock mu_lock
      alias unlock mu_unlock
      alias try_lock mu_try_lock
      alias synchronize mu_synchronize
    }
  end  

  def Mutex_m.append_features(cl)
    super
    define_aliases(cl) unless cl.instance_of?(Module)
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
      Mutex_m.define_aliases(class<<self;self;end)
    end
    mu_initialize
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
    result = false
    Thread.critical = true
    unless @mu_locked
      @mu_locked = true
      result = true
    end
    Thread.critical = false
    result
  end
  
  def mu_lock
    while (Thread.critical = true; @mu_locked)
      @mu_waiting.push Thread.current
      Thread.stop
    end
    @mu_locked = true
    Thread.critical = false
    self
  end
  
  def mu_unlock
    return unless @mu_locked
    Thread.critical = true
    wait = @mu_waiting
    @mu_waiting = []
    @mu_locked = false
    Thread.critical = false
    for w in wait
      w.run
    end
    self
  end
  
  private
  
  def mu_initialize
    @mu_waiting = []
    @mu_locked = false;
  end

  def initialize(*args)
    mu_initialize
    super
  end
end
