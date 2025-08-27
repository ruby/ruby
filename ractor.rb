# \Ractor is an Actor-model abstraction for Ruby that provides thread-safe parallel execution.
#
# Ractor.new makes a new \Ractor, which can run in parallel.
#
#     # The simplest ractor
#     r = Ractor.new {puts "I am in Ractor!"}
#     r.join # wait for it to finish
#     # Here, "I am in Ractor!" is printed
#
# Ractors do not share all objects with each other. There are two main benefits to this: across ractors, thread-safety
# concerns such as data-races and race-conditions are not possible. The other benefit is parallelism.
#
# To achieve this, object sharing is limited across ractors.
# For example, unlike in threads, ractors can't access all the objects available in other ractors. Even objects normally
# available through variables in the outer scope are prohibited from being used across ractors.
#
#     a = 1
#     r = Ractor.new {puts "I am in Ractor! a=#{a}"}
#     # fails immediately with
#     # ArgumentError (can not isolate a Proc because it accesses outer variables (a).)
#
# The object must be explicitly shared:
#     a = 1
#     r = Ractor.new(a) { |a1| puts "I am in Ractor! a=#{a1}"}
#
# On CRuby (the default implementation), Global Virtual Machine Lock (GVL) is held per ractor, so
# ractors can perform in parallel without locking each other. This is unlike the situation with threads
# on CRuby.
#
# Instead of accessing shared state, objects should be passed to and from ractors by
# sending and receiving them as messages.
#
#     a = 1
#     r = Ractor.new do
#       a_in_ractor = receive # receive blocks until somebody passes a message
#       puts "I am in Ractor! a=#{a_in_ractor}"
#     end
#     r.send(a)  # pass it
#     r.join
#     # Here, "I am in Ractor! a=1" is printed
#
# In addition to that, any arguments passed to Ractor.new are passed to the block and available there
# as if received by Ractor.receive, and the last block value can be received with Ractor#value.
#
# == Shareable and unshareable objects
#
# When an object is sent to and from a ractor, it's important to understand whether the
# object is shareable or unshareable. Most Ruby objects are unshareable objects. Even
# frozen objects can be unshareable if they contain (through their instance variables) unfrozen
# objects.
#
# Shareable objects are those which can be used by several threads without compromising
# thread-safety, for example numbers, +true+ and +false+. Ractor.shareable? allows you to check this,
# and Ractor.make_shareable tries to make the object shareable if it's not already, and gives an error
# if it can't do it.
#
#     Ractor.shareable?(1)            #=> true -- numbers and other immutable basic values are shareable
#     Ractor.shareable?('foo')        #=> false, unless the string is frozen due to # frozen_string_literal: true
#     Ractor.shareable?('foo'.freeze) #=> true
#     Ractor.shareable?([Object.new].freeze) #=> false, inner object is unfrozen
#
#     ary = ['hello', 'world']
#     ary.frozen?                 #=> false
#     ary[0].frozen?              #=> false
#     Ractor.make_shareable(ary)
#     ary.frozen?                 #=> true
#     ary[0].frozen?              #=> true
#     ary[1].frozen?              #=> true
#
# When a shareable object is sent (via #send or Ractor.yield), no additional processing occurs
# on it. It just becomes usable by both ractors. When an unshareable object is sent, it can be
# either _copied_ or _moved_. The first is the default, and it copies the object fully by
# deep cloning (Object#clone) the non-shareable parts of its structure.
#
#     data = ['foo', 'bar'.freeze]
#     r = Ractor.new do
#       data2 = Ractor.receive
#       puts "In ractor: #{data2.object_id}, #{data2[0].object_id}, #{data2[1].object_id}"
#     end
#     r.send(data)
#     r.join
#     puts "Outside  : #{data.object_id}, #{data[0].object_id}, #{data[1].object_id}"
#
# This will output something like:
#
#     In ractor: 340, 360, 320
#     Outside  : 380, 400, 320
#
# Note that the object ids of the array and the non-frozen string inside the array have changed in
# the ractor because they are different objects. The second array's element, which is a
# shareable frozen string, is the same object.
#
# Deep cloning of objects may be slow, and sometimes impossible. Alternatively, <tt>move: true</tt> may
# be used during sending. This will <em>move</em> the unshareable object to the receiving ractor, making it
# inaccessible to the sending ractor.
#
#     data = ['foo', 'bar']
#     r = Ractor.new do
#       data_in_ractor = Ractor.receive
#       puts "In ractor: #{data_in_ractor.object_id}, #{data_in_ractor[0].object_id}"
#     end
#     r.send(data, move: true)
#     r.join
#     puts "Outside: moved? #{Ractor::MovedObject === data}"
#     puts "Outside: #{data.inspect}"
#
# This will output:
#
#     In ractor: 100, 120
#     Outside: moved? true
#     test.rb:9:in `method_missing': can not send any methods to a moved object (Ractor::MovedError)
#
# Notice that even +inspect+ (and more basic methods like <tt>__id__</tt>) is inaccessible
# on a moved object.
#
# +Class+ and +Module+ objects are shareable so the class/module definitions are shared between ractors.
# \Ractor objects are also shareable. All operations on shareable objects are thread-safe, so the thread-safety property
# will be kept. We can not define mutable shareable objects in Ruby, but C extensions can introduce them.
#
# It is prohibited to access (get) instance variables of shareable objects in other ractors if the values of the
# variables aren't shareable. This can occur because modules/classes are shareable, but they can have
# instance variables whose values are not. In non-main ractors, it's also prohibited to set instance
# variables on classes/modules (even if the value is shareable).
#
#     class C
#       class << self
#         attr_accessor :tricky
#       end
#     end
#
#     C.tricky = "unshareable".dup
#
#     r = Ractor.new(C) do |cls|
#       puts "I see #{cls}"
#       puts "I can't see #{cls.tricky}"
#       cls.tricky = true # doesn't get here, but this would also raise an error
#     end
#     r.join
#     # I see C
#     # can not access instance variables of classes/modules from non-main Ractors (RuntimeError)
#
# Ractors can access constants if they are shareable. The main \Ractor is the only one that can
# access non-shareable constants.
#
#     GOOD = 'good'.freeze
#     BAD = 'bad'.dup
#
#     r = Ractor.new do
#       puts "GOOD=#{GOOD}"
#       puts "BAD=#{BAD}"
#     end
#     r.join
#     # GOOD=good
#     # can not access non-shareable objects in constant Object::BAD by non-main Ractor. (NameError)
#
#     # Consider the same C class from above
#
#     r = Ractor.new do
#       puts "I see #{C}"
#       puts "I can't see #{C.tricky}"
#     end
#     r.join
#     # I see C
#     # can not access instance variables of classes/modules from non-main Ractors (RuntimeError)
#
# See also the description of <tt># shareable_constant_value</tt> pragma in
# {Comments syntax}[rdoc-ref:syntax/comments.rdoc] explanation.
#
# == Ractors vs threads
#
# Each ractor has its own main Thread. New threads can be created from inside ractors
# (and, on CRuby, they share the GVL with other threads of this ractor).
#
#     r = Ractor.new do
#       a = 1
#       Thread.new {puts "Thread in ractor: a=#{a}"}.join
#     end
#     r.join
#     # Here "Thread in ractor: a=1" will be printed
#
# == Note on code examples
#
# In the examples below, sometimes we use the following method to wait for ractors that
# are not currently blocked to finish (or to make progress).
#
#     def wait
#       sleep(0.1)
#     end
#
# It is **only for demonstration purposes** and shouldn't be used in a real code.
# Most of the time, #join is used to wait for ractors to finish.
#
# == Reference
#
# See {Ractor design doc}[rdoc-ref:ractor.md] for more details.
#
class Ractor
  #
  #  call-seq:
  #     Ractor.new(*args, name: nil) {|*args| block } -> ractor
  #
  # Create a new \Ractor with args and a block.
  #
  # The given block (Proc) will be isolated (can't access any outer variables). +self+
  # inside the block will refer to the current \Ractor.
  #
  #    r = Ractor.new { puts "Hi, I am #{self.inspect}" }
  #    r.join
  #    # Prints "Hi, I am #<Ractor:#2 test.rb:1 running>"
  #
  # Any +args+ passed are propagated to the block arguments by the same rules as
  # objects sent via #send/Ractor.receive. If an argument in +args+ is not shareable, it
  # will be copied (via deep cloning, which might be inefficient).
  #
  #    arg = [1, 2, 3]
  #    puts "Passing: #{arg} (##{arg.object_id})"
  #    r = Ractor.new(arg) {|received_arg|
  #      puts "Received: #{received_arg} (##{received_arg.object_id})"
  #    }
  #    r.join
  #    # Prints:
  #    #   Passing: [1, 2, 3] (#280)
  #    #   Received: [1, 2, 3] (#300)
  #
  # Ractor's +name+ can be set for debugging purposes:
  #
  #    r = Ractor.new(name: 'my ractor') {}; r.join
  #    p r
  #    #=> #<Ractor:#3 my ractor test.rb:1 terminated>
  #
  def self.new(*args, name: nil, &block)
    b = block # TODO: builtin bug
    raise ArgumentError, "must be called with a block" unless block
    if __builtin_cexpr!("RBOOL(ruby_single_main_ractor)")
      Kernel.warn("Ractor is experimental, and the behavior may change in future versions of Ruby! " \
           "Also there are many implementation issues.", uplevel: 0, category: :experimental)
    end
    loc = caller_locations(1, 1).first
    loc = "#{loc.path}:#{loc.lineno}"
    __builtin_ractor_create(loc, name, args, b)
  end

  # Returns the currently executing Ractor.
  #
  #   Ractor.current #=> #<Ractor:#1 running>
  def self.current
    __builtin_cexpr! %q{
      rb_ractor_self(rb_ec_ractor_ptr(ec));
    }
  end

  # Returns the number of Ractors currently running or blocking (waiting).
  #
  #    Ractor.count                   #=> 1
  #    r = Ractor.new(name: 'example') { Ractor.receive }
  #    Ractor.count                   #=> 2 (main + example ractor)
  #    r << 42                        # r's Ractor.receive will resume
  #    r.join                         # wait for r's termination
  #    Ractor.count                   #=> 1
  def self.count
    __builtin_cexpr! %q{
      ULONG2NUM(GET_VM()->ractor.cnt);
    }
  end

  #
  # call-seq:
  #    Ractor.select(*ports) -> [...]
  #
  # TBD
  def self.select(*ports)
    raise ArgumentError, 'specify at least one ractor or `yield_value`' if ports.empty?

    monitors = {} # Ractor::Port => Ractor

    ports = ports.map do |arg|
      case arg
      when Ractor
        port = Ractor::Port.new
        monitors[port] = arg
        arg.monitor port
        port
      when Ractor::Port
        arg
      else
        raise ArgumentError, "should be Ractor::Port or Ractor"
      end
    end

    begin
      result_port, obj = __builtin_ractor_select_internal(ports)

      if r = monitors[result_port]
        [r, r.value]
      else
        [result_port, obj]
      end
    ensure
      # close all ports for join
      monitors.each do |port, r|
        r.unmonitor port
        port.close
      end
    end
  end

  #
  # call-seq:
  #    Ractor.receive -> obj
  #
  # Receive a message from the default port.
  def self.receive
    Ractor.current.default_port.receive
  end

  class << self
    alias recv receive
  end

  # same as Ractor.receive
  private def receive
    default_port.receive
  end
  alias recv receive

  #
  # call-seq:
  #   ractor.send(msg) -> self
  #
  # It is equivalent to default_port.send(msg)
  def send(...)
    default_port.send(...)
    self
  end
  alias << send

  def inspect
    loc  = __builtin_cexpr! %q{ RACTOR_PTR(self)->loc }
    name = __builtin_cexpr! %q{ RACTOR_PTR(self)->name }
    id   = __builtin_cexpr! %q{ UINT2NUM(rb_ractor_id(RACTOR_PTR(self))) }
    status = __builtin_cexpr! %q{
      rb_str_new2(ractor_status_str(RACTOR_PTR(self)->status_))
    }
    "#<Ractor:##{id}#{name ? ' '+name : ''}#{loc ? " " + loc : ''} #{status}>"
  end

  alias to_s inspect

  # The name set in Ractor.new, or +nil+.
  def name
    __builtin_cexpr! %q{RACTOR_PTR(self)->name}
  end

  class RemoteError
    # The Ractor an uncaught exception is raised in.
    attr_reader :ractor
  end

  #
  #  call-seq:
  #     Ractor.current.close -> true | false
  #
  # Closes default_port. Closing port is allowed only by the ractor which creates this port.
  # So this close method also allowed by the current Ractor.
  #
  def close
    default_port.close
  end

  #
  # call-seq:
  #    Ractor.shareable?(obj) -> true | false
  #
  # Checks if the object is shareable by ractors.
  #
  #     Ractor.shareable?(1)            #=> true -- numbers and other immutable basic values are frozen
  #     Ractor.shareable?('foo')        #=> false, unless the string is frozen due to # frozen_string_literal: true
  #     Ractor.shareable?('foo'.freeze) #=> true
  #
  # See also the "Shareable and unshareable objects" section in the \Ractor class docs.
  def self.shareable? obj
    __builtin_cexpr! %q{
      RBOOL(rb_ractor_shareable_p(obj));
    }
  end

  #
  # call-seq:
  #    Ractor.make_shareable(obj, copy: false) -> shareable_obj
  #
  # Make +obj+ shareable between ractors.
  #
  # +obj+ and all the objects it refers to will be frozen, unless they are
  # already shareable.
  #
  # If +copy+ keyword is +true+, it will copy objects before freezing them, and will not
  # modify +obj+ or its internal objects.
  #
  # Note that the specification and implementation of this method are not
  # mature and may be changed in the future.
  #
  #   obj = ['test']
  #   Ractor.shareable?(obj)     #=> false
  #   Ractor.make_shareable(obj) #=> ["test"]
  #   Ractor.shareable?(obj)     #=> true
  #   obj.frozen?                #=> true
  #   obj[0].frozen?             #=> true
  #
  #   # Copy vs non-copy versions:
  #   obj1 = ['test']
  #   obj1s = Ractor.make_shareable(obj1)
  #   obj1.frozen?                        #=> true
  #   obj1s.object_id == obj1.object_id   #=> true
  #   obj2 = ['test']
  #   obj2s = Ractor.make_shareable(obj2, copy: true)
  #   obj2.frozen?                        #=> false
  #   obj2s.frozen?                       #=> true
  #   obj2s.object_id == obj2.object_id   #=> false
  #   obj2s[0].object_id == obj2[0].object_id #=> false
  #
  # See also the "Shareable and unshareable objects" section in the Ractor class docs.
  def self.make_shareable obj, copy: false
    if copy
      __builtin_cexpr! %q{
        rb_ractor_make_shareable_copy(obj);
      }
    else
      __builtin_cexpr! %q{
        rb_ractor_make_shareable(obj);
      }
    end
  end

  # get a value from ractor-local storage for current Ractor
  # Obsolete and use Ractor.[] instead.
  def [](sym)
    if (self != Ractor.current)
      raise RuntimeError, "Cannot get ractor local storage for non-current ractor"
    end
    Primitive.ractor_local_value(sym)
  end

  # set a value in ractor-local storage for current Ractor
  # Obsolete and use Ractor.[]= instead.
  def []=(sym, val)
    if (self != Ractor.current)
      raise RuntimeError, "Cannot set ractor local storage for non-current ractor"
    end
    Primitive.ractor_local_value_set(sym, val)
  end

  # get a value from ractor-local storage of current Ractor
  def self.[](sym)
    Primitive.ractor_local_value(sym)
  end

  # set a value in ractor-local storage of current Ractor
  def self.[]=(sym, val)
    Primitive.ractor_local_value_set(sym, val)
  end

  # call-seq:
  #   Ractor.store_if_absent(key){ init_block }
  #
  # If the corresponding value is not set, yield a value with
  # init_block and store the value in thread-safe manner.
  # This method returns corresponding stored value.
  #
  #   (1..10).map{
  #     Thread.new(it){|i|
  #       Ractor.store_if_absent(:s){ f(); i }
  #       #=> return stored value of key :s
  #     }
  #   }.map(&:value).uniq.size #=> 1 and f() is called only once
  #
  def self.store_if_absent(sym)
    Primitive.ractor_local_value_store_if_absent(sym)
  end

  # returns main ractor
  def self.main
    __builtin_cexpr! %q{
      rb_ractor_self(GET_VM()->ractor.main_ractor);
    }
  end

  # return true if the current ractor is main ractor
  def self.main?
    __builtin_cexpr! %q{
      RBOOL(GET_VM()->ractor.main_ractor == rb_ec_ractor_ptr(ec))
    }
  end

  # internal method
  def self._require feature # :nodoc:
    if main?
      super feature
    else
      Primitive.ractor_require feature
    end
  end

  class << self
    private

    # internal method that is called when the first "Ractor.new" is called
    def _activated # :nodoc:
      Kernel.prepend Module.new{|m|
        m.set_temporary_name '<RactorRequire>'

        def require feature # :nodoc: -- otherwise RDoc outputs it as a class method
          if Ractor.main?
            super
          else
            Ractor._require feature
          end
        end
      }
    end
  end

  #
  # call-seq:
  #   ractor.default_port -> port object
  #
  # return default port of the Ractor.
  #
  def default_port
    __builtin_cexpr! %q{
      ractor_default_port_value(RACTOR_PTR(self))
    }
  end

  #
  # call-seq:
  #    ractor.join -> self
  #
  # Wait for the termination of the Ractor.
  # If the Ractor was aborted (terminated with an exception),
  # Ractor#value is called to raise an exception.
  #
  #     Ractor.new{}.join #=> ractor
  #
  #     Ractor.new{ raise "foo" }.join
  #     #=> raise an exception "foo (RuntimeError)"
  #
  def join
    port = Port.new

    self.monitor port
    if port.receive == :aborted
      __builtin_ractor_value
    end

    self
  ensure
    port.close
  end

  #
  # call-seq:
  #    ractor.value -> obj
  #
  # Waits for +ractor+ to complete, using #join, and return its value or raise
  # the exception which terminated the Ractor. The value will not be copied even
  # if it is unshareable object. Therefore at most 1 Ractor can get a value.
  #
  #   r = Ractor.new{ [1, 2] }
  #   r.value #=> [1, 2] (unshareable object)
  #
  #   Ractor.new(r){|r| r.value} #=> Ractor::Error
  #
  def value
    self.join
    __builtin_ractor_value
  end

  # keep it for compatibility
  def take
    Kernel.warn("Ractor#take was deprecated and use Ractor#value instead. This method will be removed after the end of Aug 2025", uplevel: 0)
    self.value
  end

  #
  # call-seq:
  #    ractor.monitor(port) -> self
  #
  # Register port as a monitoring port. If the ractor terminated,
  # the port received a Symbol object.
  # :exited will be sent if the ractor terminated without an exception.
  # :aborted will be sent if the ractor terminated with a exception.
  #
  #     r = Ractor.new{ some_task() }
  #     r.monitor(port = Ractor::Port.new)
  #     port.receive #=> :exited and r is terminated
  #
  #     r = Ractor.new{ raise "foo" }
  #     r.monitor(port = Ractor::Port.new)
  #     port.receive #=> :terminated and r is terminated with an exception "foo"
  #
  def monitor port
    __builtin_ractor_monitor(port)
  end

  #
  # call-seq:
  #    ractor.unmonitor(port) -> self
  #
  # Unregister port from the monitoring ports.
  #
  def unmonitor port
    __builtin_ractor_unmonitor(port)
  end

  # \Port objects transmit messages between Ractors.
  class Port
    #
    # call-seq:
    #    port.receive -> msg
    #
    # Receive a message to the port (which was sent there by Port#send).
    #
    #     port = Ractor::Port.new
    #     r = Ractor.new port do |port|
    #       port.send('message1')
    #     end
    #
    #     v1 = port.receive
    #     puts "Received: #{v1}"
    #     r.join
    #     # Here will be printed: "Received: message1"
    #
    # The method blocks if the message queue is empty.
    #
    #     port = Ractor::Port.new
    #     r = Ractor.new port do |port|
    #       wait
    #       puts "Still not received"
    #       port.send('message1')
    #       wait
    #       puts "Still received only one"
    #       port.send('message2')
    #     end
    #     puts "Before first receive"
    #     v1 = port.receive
    #     puts "Received: #{v1}"
    #     v2 = port.receive
    #     puts "Received: #{v2}"
    #     r.join
    #
    # Output:
    #
    #     Before first receive
    #     Still not received
    #     Received: message1
    #     Still received only one
    #     Received: message2
    #
    # If close_incoming was called on the ractor, the method raises Ractor::ClosedError
    # if there are no more messages in the message queue:
    #
    #     port = Ractor::Port.new
    #     port.close
    #     port.receive #=> raise Ractor::ClosedError
    #
    def receive
      __builtin_cexpr! %q{
        ractor_port_receive(ec, self)
      }
    end

    #
    # call-seq:
    #    port.send(msg, move: false) -> self
    #
    # Send a message to a port to be accepted by port.receive.
    #
    #     port = Ractor::Port.new
    #     r = Ractor.new do
    #       r.send 'message'
    #     end
    #     value = port.receive
    #     puts "Received #{value}"
    #     # Prints: "Received: message"
    #
    # The method is non-blocking (will return immediately even if the ractor is not ready
    # to receive anything):
    #
    #     port = Ractor::Port.new
    #     r = Ractor.new(port) do |port|
    #       port.send 'test'}
    #       puts "Sent successfully"
    #       # Prints: "Sent successfully" immediately
    #     end
    #
    # An attempt to send to a port which already closed its execution will raise Ractor::ClosedError.
    #
    #   r = Ractor.new {Ractor::Port.new}
    #   r.join
    #   p r
    #   # "#<Ractor:#6 (irb):23 terminated>"
    #   port = r.value
    #   port.send('test') # raise Ractor::ClosedError
    #
    # If the +obj+ is unshareable, by default it will be copied into the receiving ractor by deep cloning.
    #
    # If the object is shareable, it only send a reference to the object without cloning.
    #
    def send obj, move: false
      __builtin_cexpr! %q{
        ractor_port_send(ec, self, obj, move)
      }
    end

    alias << send

    #
    # call-seq:
    #    port.close
    #
    # Close the port. On the closed port, sending is not prohibited.
    # Receiving is also not allowed if there is no sent messages arrived before closing.
    #
    #     port = Ractor::Port.new
    #     Ractor.new port do |port|
    #       port.send 1 # OK
    #       port.send 2 # OK
    #       port.close
    #       port.send 3 # raise Ractor::ClosedError
    #     end
    #
    #     port.receive #=> 1
    #     port.receive #=> 2
    #     port.receive #=> raise Ractor::ClosedError
    #
    # Now, only a Ractor which creates the port is allowed to close ports.
    #
    #     port = Ractor::Port.new
    #     Ractor.new port do |port|
    #       port.close #=> closing port by other ractors is not allowed (Ractor::Error)
    #     end.join
    #
    def close
      __builtin_cexpr! %q{
        ractor_port_close(ec, self)
      }
    end

    #
    # call-seq:
    #    port.closed? -> true/false
    #
    # Return the port is closed or not.
    def closed?
      __builtin_cexpr! %q{
        ractor_port_closed_p(ec, self);
      }
    end

    #
    # call-seq:
    #    port.inspect -> string
    def inspect
      "#<Ractor::Port to:\##{
        __builtin_cexpr! "SIZET2NUM(rb_ractor_id((RACTOR_PORT_PTR(self)->r)))"
      } id:#{
        __builtin_cexpr! "SIZET2NUM(ractor_port_id(RACTOR_PORT_PTR(self)))"
      }>"
    end
  end
end
