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
#    a.new     #  NoMethodError - new is private ...
#
# *  ``The instance'' is created at instanciation time, in other words
#    the first call of Klass.instance(), thus
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
# This is achieved by marking
# *  Klass.new and Klass.allocate - as private
# *  removing #clone and #dup and modifying 
# *  Klass.inherited(sub_klass) and Klass.clone()  - 
#    to ensure that the Singleton pattern is properly
#    inherited and cloned.
#
# In addition Klass is providing the additional class methods
# *  Klass.instance()  -  returning ``the instance''. After a successful
#    self modifying instanciating first call the method body is a simple
#           def Klass.instance()
#               return @__instance__
#           end
# *  Klass._load(str)  -  calls instance()
# *  Klass._instanciate?()  -  returning ``the instance'' or nil
#    This hook method puts a second (or nth) thread calling
#    Klass.instance() on a waiting loop. The return value signifies
#    the successful completion or premature termination of the
#    first, or more generally, current instanciating thread.
#
# The sole instance method of Singleton is
# *  _dump(depth) - returning the empty string.  Marshalling strips
#    by default all state information, e.g. instance variables and taint
#    state, from ``the instance''.  Providing custom _load(str) and
#    _dump(depth) hooks allows the (partially) resurrections of a
#    previous state of ``the instance''.

module Singleton
    private 
    #  default marshalling strategy
    def _dump(depth=-1) '' end
    
    class << self
        #  extending an object with Singleton is a bad idea
        undef_method :extend_object
        private
        def append_features(mod)
            #  This catches ill advisted inclusions of Singleton in
            #  singletons types (sounds like an oxymoron) and 
            #  helps out people counting on transitive mixins
            unless mod.instance_of?(Class)
                raise TypeError, "Inclusion of the OO-Singleton module in module #{mod}"
            end 
            unless (class << mod; self end) <= (class << Object; self end)
                raise TypeError, "Inclusion of the OO-Singleton module in singleton type"
            end
            super
        end
        def included(klass)
            #  remove build in copying methods
            klass.class_eval do 
	      define_method(:clone) {raise TypeError, "can't clone singleton #{self.type}"}
            end
            
            #  initialize the ``klass instance variable'' @__instance__ to nil
            klass.instance_eval do @__instance__ = nil end
            class << klass
                #  a main point of the whole exercise - make
                #  new and allocate private
                private  :new, :allocate
                
                #  declare the self modifying klass#instance method
                define_method(:instance, Singleton::FirstInstanceCall) 
                 
                #  simple waiting loop hook - should do in most cases
                #  note the pre/post-conditions of a thread-critical state
                private   
                def _instanciate?()
                    while false.equal?(@__instance__)
                        Thread.critical = false
                        sleep(0.08)  
                        Thread.critical = true
                    end
                    @__instance__
                end
                
                #  default Marshalling strategy
                def _load(str) instance end    
                 
               #  ensure that the Singleton pattern is properly inherited   
                def inherited(sub_klass)
                    super
                    sub_klass.instance_eval do @__instance__ = nil end
                    class << sub_klass
                        define_method(:instance, Singleton::FirstInstanceCall) 
                    end
                end 
                
                public
                #  properly clone the Singleton pattern. Question - Did
                #  you know that duping doesn't copy class methods?
                def clone
                    res = super
                    res.instance_eval do @__instance__ = nil end
                    class << res
                        define_method(:instance, Singleton::FirstInstanceCall)
                    end
                    res
                end
            end   #  of << klass
        end       #  of included
    end           #  of << Singleton
    
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
                    def self.instance() @__instance__ end
                else
                    @__instance__ = nil #  failed instance creation
                end
            end
        elsif  _instanciate?()
            Thread.critical = false    
        else
            @__instance__  = false
            Thread.critical = false
            begin
                @__instance__ = new
            ensure
                if @__instance__
                    def self.instance() @__instance__ end
                else
                    @__instance__ = nil
                end
            end
        end
        @__instance__ 
    end
end




if __FILE__ == $0

def num_of_instances(klass)
    "#{ObjectSpace.each_object(klass){}} #{klass} instance(s)"
end 

# The basic and most important example.  The latter examples demonstrate
# advanced features that have no relevance for the general usage

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



puts "\nThreaded example with exception and customized #_instanciate?() hook"; p
Thread.abort_on_exception = false

class Ups < SomeSingletonClass
    def initialize
        type.__sleep
        puts "initialize called by thread ##{Thread.current[:i]}"
    end
    class << self
        def _instanciate?
            @enter.push Thread.current[:i]
            while false.equal?(@__instance__)
                Thread.critical = false
                sleep 0.04 
                Thread.critical = true
            end
            @leave.push Thread.current[:i]
            @__instance__
        end
        def __sleep
            sleep(rand(0.08))
        end 
        def allocate
            __sleep
            def self.allocate; __sleep; super() end
            raise  "boom - allocation in thread ##{Thread.current[:i]} aborted"
        end
        def instanciate_all
            @enter = []
            @leave = []
            1.upto(9) do |i|  
                Thread.new do 
                    begin
                        Thread.current[:i] = i
                        __sleep
                        instance
                    rescue RuntimeError => mes
                        puts mes
                    end
                end
            end
            puts "Before there were #{num_of_instances(self)}"
            sleep 5
            puts "Now there is #{num_of_instances(self)}"
            puts "#{@enter.join '; '} was the order of threads entering the waiting loop"
            puts "#{@leave.join '; '} was the order of threads leaving the waiting loop"
        end
    end
end

Ups.instanciate_all
#  results in message like
#  Before there were 0 Ups instances
#  boom - allocation in thread #8 aborted
#  initialize called by thread #3
#  Now there is 1 Ups instance
#  2; 3; 6; 1; 7; 5; 9; 4 was the order of threads entering the waiting loop
#  3; 2; 1; 7; 6; 5; 4; 9 was the order of threads leaving the waiting loop

puts "\nLets see if class level cloning really works"
Yup = Ups.clone
def Yup.allocate
    __sleep
    def self.allocate; __sleep; super() end
    raise  "boom - allocation in thread ##{Thread.current[:i]} aborted"
end
Yup.instanciate_all


puts "\n","Customized marshalling"
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
    def Up.inherited(sub_klass)
        puts "#{sub_klass} subclasses #{self}"
    end
end


class Middle < Up
    undef_method :dup
    include Singleton
end
class Down < Middle; end

puts  "basic test is #{Down.instance == Down.instance}"  


puts "\n","Various exceptions"

begin
    module AModule
        include Singleton
    end
rescue TypeError => mes
    puts mes  #=> Inclusion of the OO-Singleton module in module AModule
end

begin
    class << 'aString'
        include Singleton
    end
rescue TypeError => mes
    puts mes  # => Inclusion of the OO-Singleton module in singleton type
end

begin
    'aString'.extend Singleton
rescue NoMethodError => mes
    puts mes  #=> undefined method `extend_object' for Singleton:Module
end

end
