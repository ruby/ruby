#
# $Id$
# Copyright (C) 1998 Yukihiro Matsumoto. All rights reserved. 

# The ObjectSpace extension:
#
#  ObjectSpace.define_finalizer(obj, proc=lambda())
#
#    Defines the finalizer for the specified object.
#
#  ObjectSpace.undefine_finalizer(obj)
#
#    Removes the finalizers for the object.  If multiple finalizers are
#    defined for the object,  all finalizers will be removed.
#

module ObjectSpace
  Finalizers = {}
  def define_finalizer(obj, proc=lambda())
    ObjectSpace.call_finalizer(obj)
    if assoc = Finalizers[obj.id]
      assoc.push(proc)
    else
      Finalizers[obj.id] = [proc]
    end
  end
  def undefine_finalizer(obj)
    Finalizers.delete(obj.id)
  end
  module_function :define_finalizer, :undefine_finalizer

  Generic_Finalizer = proc {|id|
    if Finalizers.key? id
      for proc in Finalizers[id]
	proc.call(id)
      end
      Finalizers.delete(id)
    end
  }
  add_finalizer Generic_Finalizer
end
