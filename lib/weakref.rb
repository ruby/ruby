# Weak Reference class that does not bother GCing.
#
# Usage:
#   foo = Object.new
#   foo.hash
#   foo = WeakRef.new(foo)
#   foo.hash
#   ObjectSpace.garbage_collect
#   foo.hash	# => Raises WeakRef::RefError (because original GC'ed)

require "delegate"

class WeakRef<Delegator

  class RefError<StandardError
  end

  ID_MAP =  {}
  ID_REV_MAP =  {}
  ObjectSpace.add_finalizer(lambda{|id|
			      rid = ID_MAP[id]
			      if rid
				ID_REV_MAP[rid] = nil
				ID_MAP[id] = nil
			      end
			      rid = ID_REV_MAP[id]
			      if rid
				ID_REV_MAP[id] = nil
				ID_MAP[rid] = nil
			      end
			    })
			    
  def initialize(orig)
    super
    @__id = orig.__id__
    ObjectSpace.call_finalizer orig
    ObjectSpace.call_finalizer self
    ID_MAP[@__id] = self.__id__
    ID_REV_MAP[self.id] = @__id
  end

  def __getobj__
    unless ID_MAP[@__id]
      raise RefError, "Illegal Reference - probably recycled", caller(2)
    end
    ObjectSpace._id2ref(@__id)
  end

  def weakref_alive?
    if ID_MAP[@__id]
      true
    else
      false
    end
  end

  def []
    __getobj__
  end
end

if __FILE__ == $0
  foo = Object.new
  p foo.hash			# original's hash value
  foo = WeakRef.new(foo)
  p foo.hash			# should be same hash value
  ObjectSpace.garbage_collect
  p foo.hash			# should raise exception (recycled)
end
