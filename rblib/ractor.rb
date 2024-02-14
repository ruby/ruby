# \Ractor is an Actor-model abstraction for Ruby that provides thread-safe parallel execution.
#
# Ractor.new makes a new \Ractor, which can run in parallel.
#
#     # The simplest ractor
#     r = Ractor.new {puts "I am in Ractor!"}
#     r.take # wait for it to finish
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
#     r.take
#     # Here, "I am in Ractor! a=1" is printed
#
# There are two pairs of methods for sending/receiving messages:
#
# * Ractor#send and Ractor.receive for when the _sender_ knows the receiver (push);
# * Ractor.yield and Ractor#take for when the _receiver_ knows the sender (pull);
#
# In addition to that, any arguments passed to Ractor.new are passed to the block and available there
# as if received by Ractor.receive, and the last block value is sent outside of the
# ractor as if sent by Ractor.yield.
#
# A little demonstration of a classic ping-pong:
#
#     server = Ractor.new(name: "server") do
#       puts "Server starts: #{self.inspect}"
#       puts "Server sends: ping"
#       Ractor.yield 'ping'                       # The server doesn't know the receiver and sends to whoever interested
#       received = Ractor.receive                 # The server doesn't know the sender and receives from whoever sent
#       puts "Server received: #{received}"
#     end
#
#     client = Ractor.new(server) do |srv|        # The server is sent to the client, and available as srv
#       puts "Client starts: #{self.inspect}"
#       received = srv.take                       # The client takes a message from the server
#       puts "Client received from " \
#            "#{srv.inspect}: #{received}"
#       puts "Client sends to " \
#            "#{srv.inspect}: pong"
#       srv.send 'pong'                           # The client sends a message to the server
#     end
#
#     [client, server].each(&:take)               # Wait until they both finish
#
# This will output something like:
#
#     Server starts: #<Ractor:#2 server test.rb:1 running>
#     Server sends: ping
#     Client starts: #<Ractor:#3 test.rb:8 running>
#     Client received from #<Ractor:#2 server test.rb:1 blocking>: ping
#     Client sends to #<Ractor:#2 server test.rb:1 blocking>: pong
#     Server received: pong
#
# Ractors receive their messages via the <em>incoming port</em>, and send them
# to the <em>outgoing port</em>. Either one can be disabled with Ractor#close_incoming and
# Ractor#close_outgoing, respectively. When a ractor terminates, its ports are closed
# automatically.
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
#     r.take
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
#     r.take
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
# Class and Module objects are shareable so the class/module definitions are shared between ractors.
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
#     r.take
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
#     r.take
#     # GOOD=good
#     # can not access non-shareable objects in constant Object::BAD by non-main Ractor. (NameError)
#
#     # Consider the same C class from above
#
#     r = Ractor.new do
#       puts "I see #{C}"
#       puts "I can't see #{C.tricky}"
#     end
#     r.take
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
#     r.take
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
# Most of the time, #take is used to wait for ractors to finish.
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
  #    r.take
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
  #    r.take
  #    # Prints:
  #    #   Passing: [1, 2, 3] (#280)
  #    #   Received: [1, 2, 3] (#300)
  #
  # Ractor's +name+ can be set for debugging purposes:
  #
  #    r = Ractor.new(name: 'my ractor') {}; r.take
  #    p r
  #    #=> #<Ractor:#3 my ractor test.rb:1 terminated>
  #
  def self.new(*args, name: nil, &block)
    b = block # TODO: builtin bug
    raise ArgumentError, "must be called with a block" unless block
    if __builtin_cexpr!("RBOOL(ruby_single_main_ractor)")
      warn("Ractor is experimental, and the behavior may change in future versions of Ruby! " \
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
  #    r = Ractor.new(name: 'example') { Ractor.yield(1) }
  #    Ractor.count                   #=> 2 (main + example ractor)
  #    r.take                         # wait for Ractor.yield(1)
  #    r.take                         # wait until r will finish
  #    Ractor.count                   #=> 1
  def self.count
    __builtin_cexpr! %q{
      ULONG2NUM(GET_VM()->ractor.cnt);
    }
  end

  #
  # call-seq:
  #    Ractor.select(*ractors, [yield_value:, move: false]) -> [ractor or symbol, obj]
  #
  # Wait for any ractor to have something in its outgoing port, read from this ractor, and
  # then return that ractor and the object received.
  #
  #    r1 = Ractor.new {Ractor.yield 'from 1'}
  #    r2 = Ractor.new {Ractor.yield 'from 2'}
  #
  #    r, obj = Ractor.select(r1, r2)
  #
  #    puts "received #{obj.inspect} from #{r.inspect}"
  #    # Prints: received "from 1" from #<Ractor:#2 test.rb:1 running>
  #    # But could just as well print "from r2" here, either prints could be first.
  #
  # If one of the given ractors is the current ractor, and it is selected, +r+ will contain
  # the +:receive+ symbol instead of the ractor object.
  #
  #    r1 = Ractor.new(Ractor.current) do |main|
  #      main.send 'to main'
  #      Ractor.yield 'from 1'
  #    end
  #    r2 = Ractor.new do
  #      Ractor.yield 'from 2'
  #    end
  #
  #    r, obj = Ractor.select(r1, r2, Ractor.current)
  #    puts "received #{obj.inspect} from #{r.inspect}"
  #    # Could print: received "to main" from :receive
  #
  # If +yield_value+ is provided, that value may be yielded if another ractor is calling #take.
  # In this case, the pair <tt>[:yield, nil]</tt> is returned:
  #
  #    r1 = Ractor.new(Ractor.current) do |main|
  #      puts "Received from main: #{main.take}"
  #    end
  #
  #    puts "Trying to select"
  #    r, obj = Ractor.select(r1, Ractor.current, yield_value: 123)
  #    wait
  #    puts "Received #{obj.inspect} from #{r.inspect}"
  #
  # This will print:
  #
  #    Trying to select
  #    Received from main: 123
  #    Received nil from :yield
  #
  # +move+ boolean flag defines whether yielded value will be copied (default) or moved.
  def self.select(*ractors, yield_value: yield_unspecified = true, move: false)
    raise ArgumentError, 'specify at least one ractor or `yield_value`' if yield_unspecified && ractors.empty?

    if ractors.delete Ractor.current
      do_receive = true
    else
      do_receive = false
    end

    __builtin_ractor_select_internal ractors, do_receive, !yield_unspecified, yield_value, move
  end

  #
  # call-seq:
  #    Ractor.receive -> msg
  #
  # Receive a message from the incoming port of the current ractor (which was
  # sent there by #send from another ractor).
  #
  #     r = Ractor.new do
  #       v1 = Ractor.receive
  #       puts "Received: #{v1}"
  #     end
  #     r.send('message1')
  #     r.take
  #     # Here will be printed: "Received: message1"
  #
  # Alternatively, the private instance method +receive+ may be used:
  #
  #     r = Ractor.new do
  #       v1 = receive
  #       puts "Received: #{v1}"
  #     end
  #     r.send('message1')
  #     r.take
  #     # This prints: "Received: message1"
  #
  # The method blocks if the queue is empty.
  #
  #     r = Ractor.new do
  #       puts "Before first receive"
  #       v1 = Ractor.receive
  #       puts "Received: #{v1}"
  #       v2 = Ractor.receive
  #       puts "Received: #{v2}"
  #     end
  #     wait
  #     puts "Still not received"
  #     r.send('message1')
  #     wait
  #     puts "Still received only one"
  #     r.send('message2')
  #     r.take
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
  # if there are no more messages in the incoming queue:
  #
  #     Ractor.new do
  #       close_incoming
  #       receive
  #     end
  #     wait
  #     # in `receive': The incoming port is already closed => #<Ractor:#2 test.rb:1 running> (Ractor::ClosedError)
  #
  def self.receive
    __builtin_cexpr! %q{
      ractor_receive(ec, rb_ec_ractor_ptr(ec))
    }
  end

  class << self
    alias recv receive
  end

  # same as Ractor.receive
  private def receive
    __builtin_cexpr! %q{
      ractor_receive(ec, rb_ec_ractor_ptr(ec))
    }
  end
  alias recv receive

  #
  # call-seq:
  #    Ractor.receive_if {|msg| block } -> msg
  #
  # Receive only a specific message.
  #
  # Instead of Ractor.receive, Ractor.receive_if can be given a pattern (or any
  # filter) in a block and you can choose the messages to accept that are available in
  # your ractor's incoming queue.
  #
  #     r = Ractor.new do
  #       p Ractor.receive_if{|msg| msg.match?(/foo/)} #=> "foo3"
  #       p Ractor.receive_if{|msg| msg.match?(/bar/)} #=> "bar1"
  #       p Ractor.receive_if{|msg| msg.match?(/baz/)} #=> "baz2"
  #     end
  #     r << "bar1"
  #     r << "baz2"
  #     r << "foo3"
  #     r.take
  #
  # This will output:
  #
  #     foo3
  #     bar1
  #     baz2
  #
  # If the block returns a truthy value, the message is removed from the incoming queue
  # and returned.
  # Otherwise, the message remains in the incoming queue and the next messages are checked
  # by the given block.
  #
  # If there are no messages left in the incoming queue, the method will
  # block until new messages arrive.
  #
  # If the block is escaped by break/return/exception/throw, the message is removed from
  # the incoming queue as if a truthy value had been returned.
  #
  #     r = Ractor.new do
  #       val = Ractor.receive_if{|msg| msg.is_a?(Array)}
  #       puts "Received successfully: #{val}"
  #     end
  #
  #     r.send(1)
  #     r.send('test')
  #     wait
  #     puts "2 non-matching sent, nothing received"
  #     r.send([1, 2, 3])
  #     wait
  #
  # Prints:
  #
  #     2 non-matching sent, nothing received
  #     Received successfully: [1, 2, 3]
  #
  # Note that you can not call receive/receive_if in the given block recursively.
  # You should not do any tasks in the block other than message filtration.
  #
  #     Ractor.current << true
  #     Ractor.receive_if{|msg| Ractor.receive}
  #     #=> `receive': can not call receive/receive_if recursively (Ractor::Error)
  #
  def self.receive_if &b
    Primitive.ractor_receive_if b
  end

  # same as Ractor.receive_if
  private def receive_if &b
    Primitive.ractor_receive_if b
  end

  #
  # call-seq:
  #    ractor.send(msg, move: false) -> self
  #
  # Send a message to a Ractor's incoming queue to be accepted by Ractor.receive.
  #
  #   r = Ractor.new do
  #     value = Ractor.receive
  #     puts "Received #{value}"
  #   end
  #   r.send 'message'
  #   # Prints: "Received: message"
  #
  # The method is non-blocking (will return immediately even if the ractor is not ready
  # to receive anything):
  #
  #    r = Ractor.new {sleep(5)}
  #    r.send('test')
  #    puts "Sent successfully"
  #    # Prints: "Sent successfully" immediately
  #
  # An attempt to send to a ractor which already finished its execution will raise Ractor::ClosedError.
  #
  #   r = Ractor.new {}
  #   r.take
  #   p r
  #   # "#<Ractor:#6 (irb):23 terminated>"
  #   r.send('test')
  #   # Ractor::ClosedError (The incoming-port is already closed)
  #
  # If close_incoming was called on the ractor, the method also raises Ractor::ClosedError.
  #
  #    r =  Ractor.new do
  #      sleep(500)
  #      receive
  #    end
  #    r.close_incoming
  #    r.send('test')
  #    # Ractor::ClosedError (The incoming-port is already closed)
  #    # The error is raised immediately, not when the ractor tries to receive
  #
  # If the +obj+ is unshareable, by default it will be copied into the receiving ractor by deep cloning.
  # If <tt>move: true</tt> is passed, the object is _moved_ into the receiving ractor and becomes
  # inaccessible to the sender.
  #
  #    r = Ractor.new {puts "Received: #{receive}"}
  #    msg = 'message'
  #    r.send(msg, move: true)
  #    r.take
  #    p msg
  #
  # This prints:
  #
  #    Received: message
  #    in `p': undefined method `inspect' for #<Ractor::MovedObject:0x000055c99b9b69b8>
  #
  # All references to the object and its parts will become invalid to the sender.
  #
  #    r = Ractor.new {puts "Received: #{receive}"}
  #    s = 'message'
  #    ary = [s]
  #    copy = ary.dup
  #    r.send(ary, move: true)
  #
  #    s.inspect
  #    # Ractor::MovedError (can not send any methods to a moved object)
  #    ary.class
  #    # Ractor::MovedError (can not send any methods to a moved object)
  #    copy.class
  #    # => Array, it is different object
  #    copy[0].inspect
  #    # Ractor::MovedError (can not send any methods to a moved object)
  #    # ...but its item was still a reference to `s`, which was moved
  #
  # If the object is shareable, <tt>move: true</tt> has no effect on it:
  #
  #    r = Ractor.new {puts "Received: #{receive}"}
  #    s = 'message'.freeze
  #    r.send(s, move: true)
  #    s.inspect #=> "message", still available
  #
  def send(obj, move: false)
    __builtin_cexpr! %q{
      ractor_send(ec, RACTOR_PTR(self), obj, move)
    }
  end
  alias << send

  #
  #  call-seq:
  #     Ractor.yield(msg, move: false) -> nil
  #
  # Send a message to the current ractor's outgoing port to be accepted by #take.
  #
  #    r = Ractor.new {Ractor.yield 'Hello from ractor'}
  #    puts r.take
  #    # Prints: "Hello from ractor"
  #
  # This method is blocking, and will return only when somebody consumes the
  # sent message.
  #
  #    r = Ractor.new do
  #      Ractor.yield 'Hello from ractor'
  #      puts "Ractor: after yield"
  #    end
  #    wait
  #    puts "Still not taken"
  #    puts r.take
  #
  # This will print:
  #
  #    Still not taken
  #    Hello from ractor
  #    Ractor: after yield
  #
  # If the outgoing port was closed with #close_outgoing, the method will raise:
  #
  #    r = Ractor.new do
  #      close_outgoing
  #      Ractor.yield 'Hello from ractor'
  #    end
  #    wait
  #    # `yield': The outgoing-port is already closed (Ractor::ClosedError)
  #
  # The meaning of the +move+ argument is the same as for #send.
  def self.yield(obj, move: false)
    __builtin_cexpr! %q{
      ractor_yield(ec, rb_ec_ractor_ptr(ec), obj, move)
    }
  end

  #
  #  call-seq:
  #     ractor.take -> msg
  #
  # Get a message from the ractor's outgoing port, which was put there by Ractor.yield or at ractor's
  # termination.
  #
  #   r = Ractor.new do
  #     Ractor.yield 'explicit yield'
  #     'last value'
  #   end
  #   puts r.take #=> 'explicit yield'
  #   puts r.take #=> 'last value'
  #   puts r.take # Ractor::ClosedError (The outgoing-port is already closed)
  #
  # The fact that the last value is also sent to the outgoing port means that +take+ can be used
  # as an analog of Thread#join ("just wait until ractor finishes"). However, it will raise if
  # somebody has already consumed that message.
  #
  # If the outgoing port was closed with #close_outgoing, the method will raise Ractor::ClosedError.
  #
  #    r = Ractor.new do
  #      sleep(500)
  #      Ractor.yield 'Hello from ractor'
  #    end
  #    r.close_outgoing
  #    r.take
  #    # Ractor::ClosedError (The outgoing-port is already closed)
  #    # The error would be raised immediately, not when ractor will try to receive
  #
  # If an uncaught exception is raised in the Ractor, it is propagated by take as a
  # Ractor::RemoteError.
  #
  #   r = Ractor.new {raise "Something weird happened"}
  #
  #   begin
  #     r.take
  #   rescue => e
  #     p e              #  => #<Ractor::RemoteError: thrown by remote Ractor.>
  #     p e.ractor == r  # => true
  #     p e.cause        # => #<RuntimeError: Something weird happened>
  #   end
  #
  # Ractor::ClosedError is a descendant of StopIteration, so the termination of the ractor will break
  # out of any loops that receive this message without propagating the error:
  #
  #     r = Ractor.new do
  #       3.times {|i| Ractor.yield "message #{i}"}
  #       "finishing"
  #     end
  #
  #     loop {puts "Received: " + r.take}
  #     puts "Continue successfully"
  #
  # This will print:
  #
  #     Received: message 0
  #     Received: message 1
  #     Received: message 2
  #     Received: finishing
  #     Continue successfully
  def take
    __builtin_cexpr! %q{
      ractor_take(ec, RACTOR_PTR(self))
    }
  end

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
    attr_reader :ractor
  end

  #
  #  call-seq:
  #     ractor.close_incoming -> true | false
  #
  # Closes the incoming port and returns whether it was already closed. All further attempts
  # to Ractor.receive in the ractor, and #send to the ractor will fail with Ractor::ClosedError.
  #
  #   r = Ractor.new {sleep(500)}
  #   r.close_incoming  #=> false
  #   r.close_incoming  #=> true
  #   r.send('test')
  #   # Ractor::ClosedError (The incoming-port is already closed)
  def close_incoming
    __builtin_cexpr! %q{
      ractor_close_incoming(ec, RACTOR_PTR(self));
    }
  end

  #
  # call-seq:
  #    ractor.close_outgoing -> true | false
  #
  # Closes the outgoing port and returns whether it was already closed. All further attempts
  # to Ractor.yield in the ractor, and #take from the ractor will fail with Ractor::ClosedError.
  #
  #   r = Ractor.new {sleep(500)}
  #   r.close_outgoing  #=> false
  #   r.close_outgoing  #=> true
  #   r.take
  #   # Ractor::ClosedError (The outgoing-port is already closed)
  def close_outgoing
    __builtin_cexpr! %q{
      ractor_close_outgoing(ec, RACTOR_PTR(self));
    }
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

  # get a value from ractor-local storage
  def [](sym)
    Primitive.ractor_local_value(sym)
  end

  # set a value in ractor-local storage
  def []=(sym, val)
    Primitive.ractor_local_value_set(sym, val)
  end

  # returns main ractor
  def self.main
    __builtin_cexpr! %q{
      rb_ractor_self(GET_VM()->ractor.main_ractor);
    }
  end
end
