#  Delegation class that delegates even methods defined in super class,
# which can not be covered with normal method_missing hack.
#  
#  Delegator is the abstract delegation class. Need to redefine
# `__getobj__' method in the subclass.  SimpleDelegator is the 
# concrete subclass for simple delegation.
#
# Usage:
#   foo = Object.new
#   foo = SimpleDelegator.new(foo)
#   foo.type # => Object

class Delegator

  def initialize(obj)
    preserved = ["id", "equal?", "__getobj__"]
    for t in self.type.ancestors
      preserved |= t.instance_methods
      break if t == Delegator
    end
    for method in obj.methods
      next if preserved.include? method
      eval "def self.#{method}(*args,&block); __getobj__.__send__(:#{method}, *args,&block); end"
    end
  end

  def __getobj__
    raise NotImplementError, "need to define `__getobj__'"
  end

end

class SimpleDelegator<Delegator

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

# backword compatibility ^_^;;;
Delegater = Delegator
SimpleDelegater = SimpleDelegator

if __FILE__ == $0
  foo = Object.new
  foo = SimpleDelegator.new(foo)
  p foo.type # => Object
end
