#
# $Id$
# Copyright (C) 1998 Yukihiro Matsumoto. All rights reserved. 

# The ObjectSpace extention:
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
  Finalizer = {}
  def define_finalizer(obj, proc=lambda())
    ObjectSpace.call_finalizer(obj)
    if assoc = Finalizer[obj.id]
      assoc.push(proc)
    else
      Finalizer[obj.id] = [proc]
    end
  end
  def undefine_finalizer(obj)
    Finalizer.delete(obj.id)
  end
  module_function :define_finalizer, :remove_finalizer

  Generic_Finalizer = proc {|id|
    if Finalizer.key? id
      for proc in Finalizer[id]
	proc.call(id)
      end
      Finalizer.delete(id)
    end
  }
  add_finalizer Generic_Finalizer
end
