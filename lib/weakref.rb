# Weak Reference class that does not bother GCing.
#
# Usage:
#   foo = Object.new
#   foo = Object.new
#   p foo.to_s                  # original's class
#   foo = WeakRef.new(foo)
#   p foo.to_s                  # should be same class
#   ObjectSpace.garbage_collect
#   p foo.to_s                  # should raise exception (recycled)

require "delegate"
require 'thread'

class WeakRef < Delegator

  class RefError < StandardError
  end

  @@id_map =  {}                # obj -> [ref,...]
  @@id_rev_map =  {}            # ref -> obj
  @@mutex = Mutex.new
  @@final = lambda {|id|
    @@mutex.synchronize {
      rids = @@id_map[id]
      if rids
        for rid in rids
          @@id_rev_map.delete(rid)
        end
        @@id_map.delete(id)
      end
      rid = @@id_rev_map[id]
      if rid
        @@id_rev_map.delete(id)
        @@id_map[rid].delete(id)
        @@id_map.delete(rid) if @@id_map[rid].empty?
      end
    }
  }

  def initialize(orig)
    @__id = orig.object_id
    ObjectSpace.define_finalizer orig, @@final
    ObjectSpace.define_finalizer self, @@final
    @@mutex.synchronize {
      @@id_map[@__id] = [] unless @@id_map[@__id]
    }
    @@id_map[@__id].push self.object_id
    @@id_rev_map[self.object_id] = @__id
    super
  end

  def __getobj__
    unless @@id_rev_map[self.object_id] == @__id
      Kernel::raise RefError, "Invalid Reference - probably recycled", Kernel::caller(2)
    end
    begin
      ObjectSpace._id2ref(@__id)
    rescue RangeError
      Kernel::raise RefError, "Invalid Reference - probably recycled", Kernel::caller(2)
    end
  end
  def __setobj__(obj)
  end

  def weakref_alive?
    @@id_rev_map[self.object_id] == @__id
  end
end

if __FILE__ == $0
#  require 'thread'
  foo = Object.new
  p foo.to_s                    # original's class
  foo = WeakRef.new(foo)
  p foo.to_s                    # should be same class
  ObjectSpace.garbage_collect
  ObjectSpace.garbage_collect
  p foo.to_s                    # should raise exception (recycled)
end
