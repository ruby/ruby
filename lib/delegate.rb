#  Delegation class that delegates even methods defined in super class,
# which can not be covered with normal method_missing hack.
#  
#  Delegator is the abstract delegation class. Need to redefine
# `__getobj__' method in the subclass.  SimpleDelegator is the 
# concrete subclass for simple delegation.
#
# Usage:
#   foo = Object.new
#   foo2 = SimpleDelegator.new(foo)
#   foo.hash == foo2.hash # => true

class Delegator

  def initialize(obj)
    preserved = ::Kernel.instance_methods
    for t in self.type.ancestors
      preserved |= t.instance_methods
      break if t == Delegator
    end
    preserved -= ["__getobj__","to_s","nil?","to_a","hash","dup","==","=~"]
    for method in obj.methods
      next if preserved.include? method
      eval <<EOS
def self.#{method}(*args, &block)
  begin
    __getobj__.__send__(:#{method}, *args, &block)
  rescue Exception
    n = if /:in `__getobj__'$/ =~ $@[0] then 1 else 2 end #`
    $@[1,n] = nil
    raise
  end
end
EOS
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

# backward compatibility ^_^;;;
Delegater = Delegator
SimpleDelegater = SimpleDelegator

if __FILE__ == $0
  foo = Object.new
  def foo.test
    raise 'this is OK'
  end
  foo2 = SimpleDelegator.new(foo)
  p foo.hash == foo2.hash	# => true
  foo.test			# raise error!
end
