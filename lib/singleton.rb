# The Singleton module implements the Singleton pattern.
#
# Usage:
#    class Klass
#       include Singleton
#       # ...
#    end
#
# *  this ensures that only one instance of Klass lets call it
#    ``the instance'' can be created.
#
#    a,b  = Klass.instance, Klass.instance
#    a == b   # => true
#    a.new    #  NoMethodError - new is private ...
#
# *  ``The instance'' is created at instantiation time, in other
#    words the first call of Klass.instance(), thus
#
#    class OtherKlass
#        include Singleton
#        # ...
#    end
#    ObjectSpace.each_object(OtherKlass){} # => 0.
#
# *  This behavior is preserved under inheritance and cloning.
#
#
#
# This is achieved by marking
# *  Klass.new and Klass.allocate - as private
#
# Providing (or modifying) the class methods
# *  Klass.inherited(sub_klass) and Klass.clone()  - 
#    to ensure that the Singleton pattern is properly
#    inherited and cloned.
#
# *  Klass.instance()  -  returning ``the instance''. After a
#    successful self modifying (normally the first) call the
#    method body is a simple:
#
#       def Klass.instance()
#         return @__instance__
#       end
#
# *  Klass._load(str)  -  calling Klass.instance()
#
# *  Klass._instantiate?()  -  returning ``the instance'' or
#    nil. This hook method puts a second (or nth) thread calling
#    Klass.instance() on a waiting loop. The return value
#    signifies the successful completion or premature termination
#    of the first, or more generally, current "instantiation thread".
#
#
# The instance method of Singleton are
# * clone and dup - raising TypeErrors to prevent cloning or duping
#
# *  _dump(depth) - returning the empty string.  Marshalling strips
#    by default all state information, e.g. instance variables and
#    taint state, from ``the instance''.  Providing custom _load(str)
#    and _dump(depth) hooks allows the (partially) resurrections of
#    a previous state of ``the instance''.



module Singleton
  #  disable build-in copying methods
  def clone
    raise TypeError, "can't clone instance of singleton #{self.class}"
  end
  def dup
    raise TypeError, "can't dup instance of singleton #{self.class}"
  end
  
  private 
  #  default marshalling strategy
  def _dump(depth=-1) 
    ''
  end
end


class << Singleton
  #  Method body of first instance call.
  FirstInstanceCall = proc do
    #  @__instance__ takes on one of the following values
    #  * nil     -  before and after a failed creation
    #  * false  -  during creation
    #  * sub_class instance  -  after a successful creation
    #  the form makes up for the lack of returns in progs
    Thread.critical = true
    if  @__instance__.nil?
      @__instance__  = false
      Thread.critical = false
      begin
        @__instance__ = new
      ensure
        if @__instance__
          class <<self
            remove_method :instance
            def instance; @__instance__ end
          end
        else
          @__instance__ = nil #  failed instance creation
        end
      end
    elsif  _instantiate?()
      Thread.critical = false    
    else
      @__instance__  = false
      Thread.critical = false
      begin
        @__instance__ = new
      ensure
        if @__instance__
          class <<self
            remove_method :instance
            def instance; @__instance__ end
          end
        else
          @__instance__ = nil
        end
      end
    end
    @__instance__
  end
  
  module SingletonClassMethods  
    # properly clone the Singleton pattern - did you know
    # that duping doesn't copy class methods?  
    def clone
      Singleton.__init__(super)
    end
    
    private
    
    #  ensure that the Singleton pattern is properly inherited   
    def inherited(sub_klass)
      super
      Singleton.__init__(sub_klass)
    end
    
    def _load(str) 
      instance 
    end
    
    # waiting-loop hook
    def _instantiate?()
      while false.equal?(@__instance__)
        Thread.critical = false
        sleep(0.08)   # timeout
        Thread.critical = true
      end
      @__instance__
    end
  end
  
  def __init__(klass)
    klass.instance_eval { @__instance__ = nil }
    class << klass
      define_method(:instance,FirstInstanceCall)
    end
    klass
  end
  
  private
  #  extending an object with Singleton is a bad idea
  undef_method :extend_object
  
  def append_features(mod)
    #  help out people counting on transitive mixins
    unless mod.instance_of?(Class)
      raise TypeError, "Inclusion of the OO-Singleton module in module #{mod}"
    end
    super
  end
  
  def included(klass)
    super
    klass.private_class_method  :new, :allocate
    klass.extend SingletonClassMethods
    Singleton.__init__(klass)
  end
end
 


if __FILE__ == $0

def num_of_instances(klass)
    "#{ObjectSpace.each_object(klass){}} #{klass} instance(s)"
end 

# The basic and most important example.

class SomeSingletonClass
  include Singleton
end
puts "There are #{num_of_instances(SomeSingletonClass)}" 

a = SomeSingletonClass.instance
b = SomeSingletonClass.instance # a and b are same object
puts "basic test is #{a == b}"

begin
  SomeSingletonClass.new
rescue  NoMethodError => mes
  puts mes
end



puts "\nThreaded example with exception and customized #_instantiate?() hook"; p
Thread.abort_on_exception = false

class Ups < SomeSingletonClass
  def initialize
    self.class.__sleep
    puts "initialize called by thread ##{Thread.current[:i]}"
  end
end
  
class << Ups
  def _instantiate?
    @enter.push Thread.current[:i]
    while false.equal?(@__instance__)
      Thread.critical = false
      sleep 0.08 
      Thread.critical = true
    end
    @leave.push Thread.current[:i]
    @__instance__
  end
  
  def __sleep
    sleep(rand(0.08))
  end
  
  def new
    begin
      __sleep
      raise  "boom - thread ##{Thread.current[:i]} failed to create instance"
    ensure
      # simple flip-flop
      class << self
        remove_method :new
      end
    end
  end
  
  def instantiate_all
    @enter = []
    @leave = []
    1.upto(9) {|i|  
      Thread.new { 
        begin
          Thread.current[:i] = i
          __sleep
          instance
        rescue RuntimeError => mes
          puts mes
        end
      }
    }
    puts "Before there were #{num_of_instances(self)}"
    sleep 3
    puts "Now there is #{num_of_instances(self)}"
    puts "#{@enter.join '; '} was the order of threads entering the waiting loop"
    puts "#{@leave.join '; '} was the order of threads leaving the waiting loop"
  end
end


Ups.instantiate_all
# results in message like
# Before there were 0 Ups instance(s)
# boom - thread #6 failed to create instance
# initialize called by thread #3
# Now there is 1 Ups instance(s)
# 3; 2; 1; 8; 4; 7; 5 was the order of threads entering the waiting loop
# 3; 2; 1; 7; 4; 8; 5 was the order of threads leaving the waiting loop


puts "\nLets see if class level cloning really works"
Yup = Ups.clone
def Yup.new
  begin
    __sleep
    raise  "boom - thread ##{Thread.current[:i]} failed to create instance"
  ensure
    # simple flip-flop
    class << self
      remove_method :new
    end
  end
end
Yup.instantiate_all


puts "\n\n","Customized marshalling"
class A
  include Singleton
  attr_accessor :persist, :die
  def _dump(depth)
    # this strips the @die information from the instance
    Marshal.dump(@persist,depth)
  end
end

def A._load(str)
  instance.persist = Marshal.load(str)
  instance
end

a = A.instance
a.persist = ["persist"]
a.die = "die"
a.taint

stored_state = Marshal.dump(a)
# change state
a.persist = nil
a.die = nil
b = Marshal.load(stored_state)
p a == b  #  => true
p a.persist  #  => ["persist"]
p a.die      #  => nil


puts "\n\nSingleton with overridden default #inherited() hook"
class Up
end
def Up.inherited(sub_klass)
  puts "#{sub_klass} subclasses #{self}"
end


class Middle < Up
  include Singleton
end

class Down < Middle; end

puts  "and basic \"Down test\" is #{Down.instance == Down.instance}\n
Various exceptions"  

begin
  module AModule
    include Singleton
  end
rescue TypeError => mes
  puts mes  #=> Inclusion of the OO-Singleton module in module AModule
end

begin
  'aString'.extend Singleton
rescue NoMethodError => mes
  puts mes  #=> undefined method `extend_object' for Singleton:Module
end

end
