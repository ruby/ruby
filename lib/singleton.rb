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
# *  Klass.new and Klass.allocate - as private and
# *  Klass.inherited(sub_klass)     - modifying to ensure
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
#    instance variables from ``the instance''.  Providing costume
#    _dump(depth) and _load(str) method allows the (partial) resurrection
#    of a previous state of ``the instance'' - see third example.
#
module Singleton
    def Singleton.included (klass)
        # should this be checked?
        # raise TypeError.new "..."  if klass.type == Module
        class << klass
            def inherited(sub_klass)
                # @__instance__ takes on one of the following values
                # * nil    - before (and after a failed) creation
                # * false - during creation
                # * sub_class instance - after a successful creation
                @__instance__ = nil
                def sub_klass.instance
                    unless @__instance__.nil?
                        # is the extra flexiblity having the hook method
                        # _wait() around ever useful?
                        _wait() while false.equal?(@__instance__)
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
                sleep(0.05)
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

# threaded example with exception
Thread.abort_on_exception = true
class Ups < SomeSingletonClass
    @__threads__=  []
    @__flip__ = nil
    @@__index__ = nil

    def initialize
        sleep(rand(0.1)/10.0)
        Thread.current[:index] = @@__index__
    end
    class << self
        def allocate
            unless @__flip__
                @__flip__ = true
                raise "boom - allocation in thread ##{@@__index__} aborted"
            end
            super()
        end
        def instanciate_all
            1.upto(5) do |@@__index__|
                sleep(rand(0.1)/10.0)
                    @__threads__.push Thread.new {
                        begin
                            instance
                        rescue RuntimeError => mes
                            puts mes
                        end
                    }
                end
            end
        def join
            @__threads__.each do |t|
                t.join
                puts "initialize called by thread ##{t[:index]}" if
t[:index]
            end
        end
    end
end


puts "There is(are) #{ObjectSpace.each_object(Ups) {}} Ups instance(s)"
    # => The is(are) 0 Ups instance(s)
Ups.instanciate_all
Ups.join # => initialize called by thread # i - where  i = 2 ... 5
p Marshal.load(Marshal.dump(Ups.instance))  == Ups.instance # => true
puts "There is(are) #{ObjectSpace.each_object(Ups) {}} Ups instance(s)"
   # => The is(are) 1 Ups instance(s)

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
