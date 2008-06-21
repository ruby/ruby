# = delegate -- Support for the Delegation Pattern
#
# Documentation by James Edward Gray II and Gavin Sinclair
#
# == Introduction
#
# This library provides three different ways to delegate method calls to an
# object.  The easiest to use is SimpleDelegator.  Pass an object to the
# constructor and all methods supported by the object will be delegated.  This
# object can be changed later.
#
# Going a step further, the top level DelegateClass method allows you to easily
# setup delegation through class inheritance.  This is considerably more
# flexible and thus probably the most common use for this library.
#
# Finally, if you need full control over the delegation scheme, you can inherit
# from the abstract class Delegator and customize as needed.  (If you find
# yourself needing this control, have a look at _forwardable_, also in the
# standard library.  It may suit your needs better.)
#
# == Notes
#
# Be advised, RDoc will not detect delegated methods.
#
# <b>delegate.rb provides full-class delegation via the
# DelegateClass() method.  For single-method delegation via
# def_delegator(), see forwardable.rb.</b>
#
# == Examples
#
# === SimpleDelegator
#
# Here's a simple example that takes advantage of the fact that
# SimpleDelegator's delegation object can be changed at any time.
#
#   class Stats
#     def initialize
#       @source = SimpleDelegator.new([])
#     end
#     
#     def stats( records )
#       @source.__setobj__(records)
#       	
#       "Elements:  #{@source.size}\n" +
#       " Non-Nil:  #{@source.compact.size}\n" +
#       "  Unique:  #{@source.uniq.size}\n"
#     end
#   end
#   
#   s = Stats.new
#   puts s.stats(%w{James Edward Gray II})
#   puts
#   puts s.stats([1, 2, 3, nil, 4, 5, 1, 2])
#
# <i>Prints:</i>
#
#   Elements:  4
#    Non-Nil:  4
#     Unique:  4
# 
#   Elements:  8
#    Non-Nil:  7
#     Unique:  6
#
# === DelegateClass()
#
# Here's a sample of use from <i>tempfile.rb</i>.
#
# A _Tempfile_ object is really just a _File_ object with a few special rules
# about storage location and/or when the File should be deleted.  That makes for
# an almost textbook perfect example of how to use delegation.
#
#   class Tempfile < DelegateClass(File)
#     # constant and class member data initialization...
#   
#     def initialize(basename, tmpdir=Dir::tmpdir)
#       # build up file path/name in var tmpname...
#     
#       @tmpfile = File.open(tmpname, File::RDWR|File::CREAT|File::EXCL, 0600)
#     
#       # ...
#     
#       super(@tmpfile)
#     
#       # below this point, all methods of File are supported...
#     end
#   
#     # ...
#   end
#
# === Delegator
#
# SimpleDelegator's implementation serves as a nice example here.
#
#    class SimpleDelegator < Delegator
#      def initialize(obj)
#        super             # pass obj to Delegator constructor, required
#        @_sd_obj = obj    # store obj for future use
#      end
# 
#      def __getobj__
#        @_sd_obj          # return object we are delegating to, required
#      end
# 
#      def __setobj__(obj)
#        @_sd_obj = obj    # change delegation object, a feature we're providing
#      end
# 
#      # ...
#    end

#
# Delegator is an abstract class used to build delegator pattern objects from
# subclasses.  Subclasses should redefine \_\_getobj\_\_.  For a concrete
# implementation, see SimpleDelegator.
#
class Delegator

  #
  # Pass in the _obj_ to delegate method calls to.  All methods supported by
  # _obj_ will be delegated to.
  #
  def initialize(obj)
    preserved = ::Kernel.public_instance_methods(false)
    preserved -= ["to_s","to_a","inspect","==","=~","==="]
    for t in self.class.ancestors
      preserved |= t.public_instance_methods(false)
      preserved |= t.private_instance_methods(false)
      preserved |= t.protected_instance_methods(false)
      break if t == Delegator
    end
    preserved << "singleton_method_added"
    for method in obj.methods
      next if preserved.include? method
      begin
	eval <<-EOS
	  def self.#{method}(*args, &block)
	    begin
	      __getobj__.__send__(:#{method}, *args, &block)
	    rescue Exception
	      $@.delete_if{|s| /:in `__getobj__'$/ =~ s} #`
	      $@.delete_if{|s| /^\\(eval\\):/ =~ s}
	      Kernel::raise
	    end
	  end
	EOS
      rescue SyntaxError
        raise NameError, "invalid identifier %s" % method, caller(4)
      end
    end
  end
  alias initialize_methods initialize

  # Handles the magic of delegation through \_\_getobj\_\_.
  def method_missing(m, *args)
    target = self.__getobj__
    unless target.respond_to?(m)
      super(m, *args)
    end
    target.__send__(m, *args)
  end

  # 
  # Checks for a method provided by this the delegate object by fowarding the 
  # call through \_\_getobj\_\_.
  # 
  def respond_to?(m, include_private = false)
    return true if super
    return self.__getobj__.respond_to?(m, include_private)
  end

  #
  # This method must be overridden by subclasses and should return the object
  # method calls are being delegated to.
  #
  def __getobj__
    raise NotImplementedError, "need to define `__getobj__'"
  end

  # Serialization support for the object returned by \_\_getobj\_\_.
  def marshal_dump
    __getobj__
  end
  # Reinitializes delegation from a serialized object.
  def marshal_load(obj)
    initialize_methods(obj)
    __setobj__(obj)
  end
end

#
# A concrete implementation of Delegator, this class provides the means to
# delegate all supported method calls to the object passed into the constructor
# and even to change the object being delegated to at a later time with
# \_\_setobj\_\_ .
#
class SimpleDelegator<Delegator

  # Pass in the _obj_ you would like to delegate method calls to.
  def initialize(obj)
    super
    @_sd_obj = obj
  end

  # Returns the current object method calls are being delegated to.
  def __getobj__
    @_sd_obj
  end

  #
  # Changes the delegate object to _obj_.
  #
  # It's important to note that this does *not* cause SimpleDelegator's methods
  # to change.  Because of this, you probably only want to change delegation
  # to objects of the same type as the original delegate.
  #
  # Here's an example of changing the delegation object.
  #
  #   names = SimpleDelegator.new(%w{James Edward Gray II})
  #   puts names[1]    # => Edward
  #   names.__setobj__(%w{Gavin Sinclair})
  #   puts names[1]    # => Sinclair
  #
  def __setobj__(obj)
    raise ArgumentError, "cannot delegate to self" if self.equal?(obj)
    @_sd_obj = obj
  end

  # Clone support for the object returned by \_\_getobj\_\_.
  def clone
    new = super
    new.__setobj__(__getobj__.clone)
    new
  end
  # Duplication support for the object returned by \_\_getobj\_\_.
  def dup
    new = super
    new.__setobj__(__getobj__.clone)
    new
  end
end

# :stopdoc:
# backward compatibility ^_^;;;
Delegater = Delegator
SimpleDelegater = SimpleDelegator
# :startdoc:

#
# The primary interface to this library.  Use to setup delegation when defining
# your class.
#
#   class MyClass < DelegateClass( ClassToDelegateTo )    # Step 1
#     def initiaize
#       super(obj_of_ClassToDelegateTo)                   # Step 2
#     end
#   end
#
def DelegateClass(superclass)
  klass = Class.new
  methods = superclass.public_instance_methods(true)
  methods -= ::Kernel.public_instance_methods(false)
  methods |= ["to_s","to_a","inspect","==","=~","==="]
  klass.module_eval {
    def initialize(obj)  # :nodoc:
      @_dc_obj = obj
    end
    def method_missing(m, *args)  # :nodoc:
      unless @_dc_obj.respond_to?(m)
        super(m, *args)
      end
      @_dc_obj.__send__(m, *args)
    end
    def respond_to?(m, include_private = false)  # :nodoc:
      return true if super
      return @_dc_obj.respond_to?(m, include_private)
    end
    def __getobj__  # :nodoc:
      @_dc_obj
    end
    def __setobj__(obj)  # :nodoc:
      raise ArgumentError, "cannot delegate to self" if self.equal?(obj)
      @_dc_obj = obj
    end
    def clone  # :nodoc:
      new = super
      new.__setobj__(__getobj__.clone)
      new
    end
    def dup  # :nodoc:
      new = super
      new.__setobj__(__getobj__.clone)
      new
    end
  }
  for method in methods
    begin
      klass.module_eval <<-EOS
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

# :enddoc:

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
