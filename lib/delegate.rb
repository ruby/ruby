#  Delegation class that delegates even methods defined in super class,
# which can not be covered with normal method_missing hack.
#  
#  Delegater is the abstract delegation class. Need to redefine
# `__getobj__' method in the subclass.  SimpleDelegater is the 
# concrete subclass for simple delegation.
#
# Usage:
#   foo = Object.new
#   foo = SimpleDelegater.new(foo)
#   foo.type # => Object

class Delegater

  def initialize(obj)
    preserved = ["id", "equal?", "__getobj__"]
    for t in self.type.ancestors
      preserved |= t.instance_methods
      break if t == Delegater
    end
    for method in obj.methods
      next if preserved.include? method
      eval "def self.#{method}(*args); __getobj__.send :#{method}, *args; end"
    end
  end

  def __getobj__
    raise NotImplementError, "need to define `__getobj__'"
  end

end

class SimpleDelegater<Delegater

  def initialize(obj)
    super
    @obj = obj
  end

  def __getobj__
    @obj
  end

  def __setobj__(obj)
    @obj = obj
  end
end
