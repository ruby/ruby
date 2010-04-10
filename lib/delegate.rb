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
#        @delegate_sd_obj = obj    # store obj for future use
#      end
#
#      def __getobj__
#        @delegate_sd_obj          # return object we are delegating to, required
#      end
#
#      def __setobj__(obj)
#        @delegate_sd_obj = obj    # change delegation object, a feature we're providing
#      end
#
#      # ...
#    end

#
# Delegator is an abstract class used to build delegator pattern objects from
# subclasses.  Subclasses should redefine \_\_getobj\_\_.  For a concrete
# implementation, see SimpleDelegator.
#
class Delegator < BasicObject
  kernel = ::Kernel.dup
  kernel.class_eval do
    [:to_s,:inspect,:=~,:!~,:===,:<=>].each do |m|
      undef_method m
    end
  end
  include kernel

  # :stopdoc:
  def self.const_missing(n)
    ::Object.const_get(n)
  end
  # :startdoc:

  #
  # Pass in the _obj_ to delegate method calls to.  All methods supported by
  # _obj_ will be delegated to.
  #
  def initialize(obj)
    __setobj__(obj)
  end

  # Handles the magic of delegation through \_\_getobj\_\_.
  def method_missing(m, *args, &block)
    target = self.__getobj__
    begin
      target.respond_to?(m) ? target.__send__(m, *args, &block) : super(m, *args, &block)
    ensure
      $@.delete_if {|t| %r"\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}:"o =~ t} if $@
    end
  end

  #
  # Checks for a method provided by this the delegate object by forwarding the
  # call through \_\_getobj\_\_.
  #
  def respond_to_missing?(m, include_private)
    r = self.__getobj__.respond_to?(m, include_private)
    if r && include_private && !self.__getobj__.respond_to?(m, false)
      warn "#{caller(3)[0]}: delegator does not forward private method \##{m}"
      return false
    end
    r
  end

  #
  # Returns true if two objects are considered same.
  #
  def ==(obj)
    return true if obj.equal?(self)
    self.__getobj__ == obj
  end

  #
  # This method must be overridden by subclasses and should return the object
  # method calls are being delegated to.
  #
  def __getobj__
    raise NotImplementedError, "need to define `__getobj__'"
  end

  #
  # This method must be overridden by subclasses and change the object delegate
  # to _obj_.
  #
  def __setobj__(obj)
    raise NotImplementedError, "need to define `__setobj__'"
  end

  # Serialization support for the object returned by \_\_getobj\_\_.
  def marshal_dump
    ivars = instance_variables.reject {|var| /\A@delegate_/ =~ var}
    [
      :__v2__,
      ivars, ivars.map{|var| instance_variable_get(var)},
      __getobj__
    ]
  end
  # Reinitializes delegation from a serialized object.
  def marshal_load(data)
    version, vars, values, obj = data
    if version == :__v2__
      vars.each_with_index{|var, i| instance_variable_set(var, values[i])}
      __setobj__(obj)
    else
      __setobj__(data)
    end
  end

  def initialize_clone(obj) # :nodoc:
    self.__setobj__(obj.__getobj__.clone)
  end
  def initialize_dup(obj) # :nodoc:
    self.__setobj__(obj.__getobj__.dup)
  end
  private :initialize_clone, :initialize_dup

  # Freeze self and target at once.
  def freeze
    __getobj__.freeze
    super
  end

  @delegator_api = self.public_instance_methods
  def self.public_api   # :nodoc:
    @delegator_api
  end
end

#
# A concrete implementation of Delegator, this class provides the means to
# delegate all supported method calls to the object passed into the constructor
# and even to change the object being delegated to at a later time with
# \_\_setobj\_\_ .
#
class SimpleDelegator<Delegator
  # Returns the current object method calls are being delegated to.
  def __getobj__
    @delegate_sd_obj
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
    @delegate_sd_obj = obj
  end
end

# :stopdoc:
def Delegator.delegating_block(mid)
  lambda do |*args, &block|
    target = self.__getobj__
    begin
      target.__send__(mid, *args, &block)
    ensure
      $@.delete_if {|t| /\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}:/o =~ t} if $@
    end
  end
end
# :startdoc:

#
# The primary interface to this library.  Use to setup delegation when defining
# your class.
#
#   class MyClass < DelegateClass( ClassToDelegateTo )    # Step 1
#     def initialize
#       super(obj_of_ClassToDelegateTo)                   # Step 2
#     end
#   end
#
def DelegateClass(superclass)
  klass = Class.new(Delegator)
  methods = superclass.public_instance_methods(true)
  methods -= ::Delegator.public_api
  methods -= [:to_s,:inspect,:=~,:!~,:===]
  klass.module_eval {
    def __getobj__  # :nodoc:
      @delegate_dc_obj
    end
    def __setobj__(obj)  # :nodoc:
      raise ArgumentError, "cannot delegate to self" if self.equal?(obj)
      @delegate_dc_obj = obj
    end
  }
  klass.module_eval do
    methods.each do |method|
      define_method(method, Delegator.delegating_block(method))
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
  ary.push 42
  ary.each {|x| p x}

  foo = Object.new
  def foo.test
    25
  end
  def foo.iter
    yield self
  end
  def foo.error
    raise 'this is OK'
  end
  foo2 = SimpleDelegator.new(foo)
  p foo2
  foo2.instance_eval{print "foo\n"}
  p foo.test == foo2.test	# => true
  p foo2.iter{[55,true]}        # => true
  foo2.error			# raise error!
end
