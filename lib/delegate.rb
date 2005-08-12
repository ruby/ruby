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
#   foo.hash == foo2.hash # => false
#
#   Foo = DelegateClass(Array)
#
#  class ExtArray<DelegateClass(Array)
#    ...
#  end

class Delegator
  preserved = ["__id__", "object_id", "__send__", "respond_to?"]
  instance_methods.each do |m|
    next if preserved.include?(m)
    undef_method m
  end

  def initialize(obj)
    __setobj__(obj)
  end

  def method_missing(m, *args)
    begin
      target = self.__getobj__
      unless target.respond_to?(m)
        super(m, *args)
      end
      target.__send__(m, *args)
    rescue Exception
      $@.delete_if{|s| /^#{__FILE__}:\d+:in `method_missing'$/ =~ s} #`
      ::Kernel::raise
    end
  end

  def respond_to?(m)
    return true if super
    return self.__getobj__.respond_to?(m)
  end

  def __getobj__
    raise NotImplementedError, "need to define `__getobj__'"
  end

  def __setobj__(obj)
    raise NotImplementedError, "need to define `__setobj__'"
  end

  def marshal_dump
    __getobj__
  end
  def marshal_load(obj)
    __setobj__(obj)
  end
end

class SimpleDelegator<Delegator
  def __getobj__
    @_sd_obj
  end

  def __setobj__(obj)
    raise ArgumentError, "cannot delegate to self" if self.equal?(obj)
    @_sd_obj = obj
  end

  def clone
    copy = super
    copy.__setobj__(__getobj__.clone)
    copy
  end
  def dup
    copy = super
    copy.__setobj__(__getobj__.dup)
    copy
  end
end

# backward compatibility ^_^;;;
Delegater = Delegator
SimpleDelegater = SimpleDelegator

#
def DelegateClass(superclass)
  klass = Class.new
  methods = superclass.public_instance_methods(true)
  methods -= [
    "__id__", "object_id", "__send__", "respond_to?",
    "initialize", "method_missing", "__getobj__", "__setobj__",
    "clone", "dup", "marshal_dump", "marshal_load",
  ]
  klass.module_eval {
    def initialize(obj)
      @_dc_obj = obj
    end
    def method_missing(m, *args)
      unless @_dc_obj.respond_to?(m)
        super(m, *args)
      end
      @_dc_obj.__send__(m, *args)
    end
    def respond_to?(m)
      return true if super
      return @_dc_obj.respond_to?(m)
    end
    def __getobj__
      @_dc_obj
    end
    def __setobj__(obj)
      raise ArgumentError, "cannot delegate to self" if self.equal?(obj)
      @_dc_obj = obj
    end
    def clone
      super
      __setobj__(__getobj__.clone)
    end
    def dup
      super
      __setobj__(__getobj__.dup)
    end
  }
  for method in methods
    begin
      klass.module_eval <<-EOS, __FILE__, __LINE__+1
        def #{method}(*args, &block)
	  begin
	    @_dc_obj.__send__(:#{method}, *args, &block)
	  rescue
	    $@[0,2] = nil
	    raise
	  end
	end
      EOS
    rescue SyntaxError
      raise NameError, "invalid identifier %s" % method, caller(3)
    end
  end
  return klass
end

if __FILE__ == $0
  class ExtArray<DelegateClass(Array)
    def initialize()
      super([])
    end
  end

  ary = ExtArray.new
  p ary.class
  ary.push 25
  p ary

  foo = Object.new
  def foo.test
    25
  end
  def foo.error
    raise 'this is OK'
  end
  foo2 = SimpleDelegator.new(foo)
  p foo.test == foo2.test	# => true
  foo2.error			# raise error!
end
