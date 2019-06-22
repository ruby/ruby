# frozen_string_literal: true
require "delegate"

# Weak Reference class that allows a referenced object to be
# garbage-collected.
#
# A WeakRef may be used exactly like the object it references.
#
# Usage:
#
#   foo = Object.new            # create a new object instance
#   p foo.to_s                  # original's class
#   foo = WeakRef.new(foo)      # reassign foo with WeakRef instance
#   p foo.to_s                  # should be same class
#   GC.start                    # start the garbage collector
#   p foo.to_s                  # should raise exception (recycled)
#

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
  # Integer, or Float.

  def initialize(orig)
    @@__map[self] = orig
  end

  def __getobj__ # :nodoc:
    obj = @@__map[self]
    if obj.is_a? ObjectSpace::WeakMap::DeadRef
      Kernel::raise(RefError, "Invalid Reference - probably recycled", Kernel::caller(2))
    else
      obj
    end
  end

  def __setobj__(obj) # :nodoc:
  end

  ##
  # Returns true if the referenced object is still alive.

  def weakref_alive?
    @@__map.key?(self) or defined?(@delegate_sd_obj)
  end
end
