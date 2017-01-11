# frozen_string_literal: false
#
#   mutex_m.rb -
#       $Release Version: 3.0$
#       $Revision: 1.7 $
#       Original from mutex.rb
#       by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       modified by matz
#       patched by akira yamada
#
# --


require 'thread'

# = mutex_m.rb
#
# When 'mutex_m' is required, any object that extends or includes Mutex_m will
# be treated like a Mutex.
#
# Start by requiring the standard library Mutex_m:
#
#   require "mutex_m.rb"
#
# From here you can extend an object with Mutex instance methods:
#
#   obj = Object.new
#   obj.extend Mutex_m
#
# Or mixin Mutex_m into your module to your class inherit Mutex instance
# methods.
#
#   class Foo
#     include Mutex_m
#     # ...
#   end
#   obj = Foo.new
#   # this obj can be handled like Mutex
#
module Mutex_m
  def Mutex_m.define_aliases(cl) # :nodoc:
    cl.module_eval %q{
      alias locked? mu_locked?
      alias lock mu_lock
      alias unlock mu_unlock
      alias try_lock mu_try_lock
      alias synchronize mu_synchronize
    }
  end

  def Mutex_m.append_features(cl) # :nodoc:
    super
    define_aliases(cl) unless cl.instance_of?(Module)
  end

  def Mutex_m.extend_object(obj) # :nodoc:
    super
    obj.mu_extended
  end

  def mu_extended # :nodoc:
    unless (defined? locked? and
            defined? lock and
            defined? unlock and
            defined? try_lock and
            defined? synchronize)
      Mutex_m.define_aliases(singleton_class)
    end
    mu_initialize
  end

  # See Mutex#synchronize
  def mu_synchronize(&block)
    @_mutex.synchronize(&block)
  end

  # See Mutex#locked?
  def mu_locked?
    @_mutex.locked?
  end

  # See Mutex#try_lock
  def mu_try_lock
    @_mutex.try_lock
  end

  # See Mutex#lock
  def mu_lock
    @_mutex.lock
  end

  # See Mutex#unlock
  def mu_unlock
    @_mutex.unlock
  end

  # See Mutex#sleep
  def sleep(timeout = nil)
    @_mutex.sleep(timeout)
  end

  private

  def mu_initialize # :nodoc:
    @_mutex = Thread::Mutex.new
  end

  def initialize(*args) # :nodoc:
    mu_initialize
    super
  end
end
