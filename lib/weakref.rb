# Weak Reference class that does not bother GCing.
#
# Usage:
#   foo = Object.new
#   foo = Object.new
#   p foo.to_s			# original's class
#   foo = WeakRef.new(foo)
#   p foo.to_s			# should be same class
#   ObjectSpace.garbage_collect
#   p foo.to_s			# should raise exception (recycled)

require "delegate"

class WeakRef<Delegator

  class RefError<StandardError
  end

  ID_MAP =  {}		    # obj -> [ref,...]
  ID_REV_MAP =  {}          # ref -> obj
  @@final = lambda{|id|
    __old_status = Thread.critical
    Thread.critical = true
    begin
      rids = ID_MAP[id]
      if rids
	for rid in rids
	  ID_REV_MAP[rid] = nil
	end
	ID_MAP[id] = nil
      end
      rid = ID_REV_MAP[id]
      if rid
	ID_REV_MAP[id] = nil
	ID_MAP[rid].delete(id)
	ID_MAP[rid] = nil if ID_MAP[rid].empty?
      end
    ensure
      Thread.critical = __old_status
    end
  }

  def initialize(orig)
    super
    @__id = orig.__id__
    ObjectSpace.define_finalizer orig, @@final
    ObjectSpace.define_finalizer self, @@final
    __old_status = Thread.critical
    begin
      Thread.critical = true
      ID_MAP[@__id] = [] unless ID_MAP[@__id]
    ensure
      Thread.critical = __old_status
    end
    ID_MAP[@__id].push self.__id__
    ID_REV_MAP[self.id] = @__id
  end

  def __getobj__
    unless ID_MAP[@__id]
      raise RefError, "Illegal Reference - probably recycled", caller(2)
    end
    begin
      ObjectSpace._id2ref(@__id)
    rescue RangeError
      raise RefError, "Illegal Reference - probably recycled", caller(2)
    end
  end

  def weakref_alive?
    if ID_MAP[@__id]
      true
    else
      false
    end
  end
end

if __FILE__ == $0
  require 'thread'
  foo = Object.new
  p foo.to_s			# original's class
  foo = WeakRef.new(foo)
  p foo.to_s			# should be same class
  ObjectSpace.garbage_collect
  p foo.to_s			# should raise exception (recycled)
end
