# The Singleton module implements the Singleton pattern - i.e.
#
# class Klass
#    include Singleton
#    # ...
# end
#
# *  ensures that only one instance of Klass called ``the instance''
#    can be created.
#
#    a,b  = Klass.instance, Klass.instance
#    a == b   # => true
#    a.new     #  NoMethodError - new is private ...
#
# *  ``The instance'' is created at instanciation time - i.e. the first call
#    of Klass.instance().
#
#    class OtherKlass
#        include Singleton
#        # ...
#    end
#    p "#{ObjectSpace.each_object(OtherKlass) {}}" # => 0
#
# *  This behavior is preserved under inheritance.
#
#
# This achieved by marking
# *  Klass.new and Klass.allocate - as private and modifying 
# *  Klass.inherited(sub_klass)     - to ensure
#     that the Singleton pattern is properly inherited.
#
# In addition Klass is provided with the class methods
# * Klass.instance()  - returning ``the instance''
# *  Klass._load(str)  - returning ``the instance''
# *  Klass._wait()     -  a hook method putting a second (or n-th)
#    thread calling Klass.instance on a waiting loop if the first call
#    to Klass.instance is still in progress.
#
# The sole instance method of Singleton is
# *  _dump(depth) - returning the empty string
#    The default Marshalling strategy is to strip all state information - i.e.
#    instance variables from ``the instance''.  Providing custom
#    _dump(depth) and _load(str) method allows the (partial) resurrection
#    of a previous state of ``the instance'' - see third example.
#
module Singleton
  def Singleton.included (klass)
    # should this be checked?
    # raise TypeError.new "..."  if klass.type == Module
    klass.module_eval {
      undef_method :clone
      undef_method :dup
    }
    class << klass
      def inherited(sub_klass)
	# @__instance__ takes on one of the following values
	# * nil    - before (and after a failed) creation
	# * false - during creation
	# * sub_class instance - after a successful creation
	sub_klass.instance_eval { @__instance__ = nil }
	def sub_klass.instance
	  unless @__instance__.nil?
	    # is the extra flexiblity having the hook method
	    # _wait() around ever useful?
	    _wait() 
	    # check for instance creation
	    return @__instance__ if @__instance__
	  end
	  Thread.critical = true
	  unless @__instance__
	    @__instance__  = false
	    Thread.critical = false
	    begin
	      @__instance__ = new
	    ensure
	      if @__instance__
		define_method(:instance) {@__instance__ }
	      else
		# failed instance creation
		@__instance__ = nil
	      end
	    end
	  else
	    Thread.critical = false
	  end
	  return @__instance__
	end
      end
      def _load(str)
	instance
      end
      def _wait
	sleep(0.05)  while false.equal?(@__instance__)
      end
      private  :new, :allocate
      # hook methods are also marked private
      private :_load,:_wait
    end
    klass.inherited klass
  end
  private
  def _dump(depth)
    return ""
  end
end

if __FILE__ == $0

#basic example
class SomeSingletonClass
    include Singleton
end
a = SomeSingletonClass.instance
b = SomeSingletonClass.instance # a and b are same object
p a == b # => true
begin
    SomeSingletonClass.new
rescue  NoMethodError => mes
    puts mes
end

# threaded example with exception and customized hook #_wait method
Thread.abort_on_exception = false
def num_of_instances(mod)
    "#{ObjectSpace.each_object(mod){}} #{mod} instance"
end 

class Ups < SomeSingletonClass
    def initialize
        type.__sleep
        puts "initialize called by thread ##{Thread.current[:i]}"
    end
    class << self
        def _wait
            @enter.push Thread.current[:i]
            sleep 0.02 while false.equal?(@__instance__)
            @leave.push Thread.current[:i]
        end
        def __sleep
            sleep (rand(0.1))
        end 
        def allocate
            __sleep
            def self.allocate; __sleep; super() end
            raise  "allocation in thread ##{Thread.current[:i]} aborted"
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
            puts "Before there were #{num_of_instances(Ups)}s"
            sleep 3
            puts "Now there is #{num_of_instances(Ups)}"
            puts "#{@enter.join "; "} was the order of threads entering the waiting loop"
            puts "#{@leave.join "; "} was the order of threads leaving the waiting loop"
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


# Customized marshalling
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

stored_state = Marshal.dump(a)
# change state
a.persist = nil
a.die = nil
b = Marshal.load(stored_state)
p a == b  #  => true
p a.persist  #  => ["persist"]
p a.die     #  => nil

end
