require "delegate"

# Weak Reference class that allows a referenced object to be
# garbage-collected.
#
# Usage:
#
#   foo = Object.new              # create a new object instance
#   p foo.to_s                    # original's class
#   foo = WeakReference.new(foo)  # reassign foo with WeakReference instance
#   p foo.get.to_s                # should be same class
#   GC.start                      # start the garbage collector
#   p foo.get                     # should be nil (recycled)
#
# == Example
#
# With help from WeakReference, we can implement our own rudimentary WeakHash class.
#
# We will call it WeakHash, since it's really just a Hash except all of it's
# keys and values can be garbage collected.
#
#     require 'weakref'
#
#     class WeakHash < Hash
#       def []= key, obj
#         super WeakReference.new(key), WeakReference.new(obj)
#       end
#       
#       def [] key
#         super(key).get
#       end
#     end
#
# This is just a simple implementation, we've extend the Hash class and changed
# Hash#store to create a new WeakReference object with +key+ and +obj+ parameters
# before passing them as our key-value pair to the hash.
#
# Let's see it in action:
#
#   omg = "lol"
#   c = WeakHash.new
#   c['foo'] = "bar"
#   c['baz'] = Object.new
#   c[omg] = "rofl"
#   puts c.inspect
#   #=> {"foo"=>"bar", "baz"=>#<Object:0x007f4ddfc6cb48>, "lol"=>"rofl"}
#
#   # Now run the garbage collector
#   GC.start
#   c['foo'] #=> nil
#   c['baz'] #=> nil
#   c[omg]   #=> "rofl"
#
# You can see the key associated with our local variable omg remained available
# while all other keys have been collected.

class WeakReference

  @@__map = ::ObjectSpace::WeakMap.new

  ##
  # Creates a weak reference to +orig+
  #
  # Raises an ArgumentError if the given +orig+ is immutable, such as Symbol,
  # Fixnum, or Float.

  def initialize(orig)
    case orig
    when true, false, nil
      @delegate_sd_obj = orig
    else
      @@__map[self] = orig
    end
  end

  ##
  # Retrieve the object referenced by this WeakReference, or nil if the object
  # has been collected.

  def get # :nodoc:
    @@__map[self] or defined?(@delegate_sd_obj) ? @delegate_sd_obj : nil
  end
  alias __getobj__ get

  ##
  # Returns true if the referenced object is still alive.

  def weakref_alive?
    !!(@@__map[self] or defined?(@delegate_sd_obj))
  end
end

# The old WeakRef class is deprecated since it can lead to hard-to-diagnose
# errors when the referenced object gets collected.

class WeakRef < Delegator

  ##
  # RefError is raised when a referenced object has been recycled by the
  # garbage collector

  class RefError < StandardError
  end

  @@__map = ::ObjectSpace::WeakMap.new

  ##
  # Creates a weak reference to +orig+
  #
  # Raises an ArgumentError if the given +orig+ is immutable, such as Symbol,
  # Fixnum, or Float.

  def initialize(orig)
    warn "WeakRef is deprecated. Use WeakReference. See https://bugs.ruby-lang.org/issues/6308."
    case orig
    when true, false, nil
      @delegate_sd_obj = orig
    else
      @@__map[self] = orig
    end
    super
  end

  def __getobj__ # :nodoc:
    @@__map[self] or defined?(@delegate_sd_obj) ? @delegate_sd_obj :
      Kernel::raise(RefError, "Invalid Reference - probably recycled", Kernel::caller(2))
  end

  def __setobj__(obj) # :nodoc:
  end

  ##
  # Returns true if the referenced object is still alive.

  def weakref_alive?
    @@__map.key?(self) or defined?(@delegate_sd_obj)
  end
end

if __FILE__ == $0
#  require 'thread'
  foo = Object.new
  p foo.to_s                    # original's class
  foo = WeakReference.new(foo)
  p foo.get.to_s                # should be same class
  ObjectSpace.garbage_collect
  ObjectSpace.garbage_collect
  p foo.get.to_s                # should raise exception (get returns nil)
end
