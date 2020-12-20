# Ractor is a Actor-model abstraction for Ruby that provides thread-safe parallel execution.
#
# To achieve this, ractors severely limit data sharing between different ractors.
# Unlike threads, ractors can't access each other's data, nor any data through variables of
# the outer scope.
#
#     # The simplest ractor
#     r = Ractor.new {puts "I am in Ractor!"}
#     r.take # allow it to finish
#     # here "I am in Ractor!" would be printed
#
#     a = 1
#     r = Ractor.new {puts "I am in Ractor! a=#{a}"}
#     # fails immediately with
#     # ArgumentError (can not isolate a Proc because it accesses outer variables (a).)
#
# On CRuby (the default implementation), Global Virtual Machine Lock (GVL) is held per ractor, so
# ractors are performed in parallel without locking each other.
#
# Instead of accessing the shared state, the data should be passed to and from ractors via
# sending and receiving messages, thus making them _actors_ ("Ractor" stands for "Ruby Actor").
#
#     a = 1
#     r = Ractor.new do
#       a_in_ractor = receive # receive blocks till somebody will pass message
#       puts "I am in Ractor! a=#{a_in_ractor}"
#     end
#     r.send(a)  # pass it
#     r.take
#     # here "I am in Ractor! a=1" would be printed
#
# There are two pairs of methods for sending/receiving messages:
#
# * Ractor#send and Ractor.receive for when the _sender_ knows the receiver (push);
# * Ractor.yield and Ractor#take for when the _receiver_ knows the sender (pull);
#
# In addition to that, an argument to Ractor.new would be passed to block and available there
# as if received by Ractor.receive, and the last block value would be sent outside of the
# ractor as if sent by Ractor.yield.
#
# A little demonstration on a classic ping-pong:
#
#     server = Ractor.new do
#       puts "Server starts: #{self.inspect}"
#       puts "Server sends: ping"
#       Ractor.yield 'ping'                       # The server doesn't know the receiver and sends to whoever interested
#       received = Ractor.receive                 # The server doesn't know the sender and receives from whoever sent
#       puts "Server received: #{received}"
#     end
#
#     client = Ractor.new(server) do |srv|        # The server is sent inside client, and available as srv
#       puts "Client starts: #{self.inspect}"
#       received = srv.take                       # The Client takes a message specifically from the server
#       puts "Client received from " \
#            "#{srv.inspect}: #{received}"
#       puts "Client sends to " \
#            "#{srv.inspect}: pong"
#       srv.send 'pong'                           # The client sends a message specifically to the server
#     end
#
#     [client, server].each(&:take)               # Wait till they both finish
#
# This will output:
#
#     Server starts: #<Ractor:#2 test.rb:1 running>
#     Server sends: ping
#     Client starts: #<Ractor:#3 test.rb:8 running>
#     Client received from #<Ractor:#2 rac.rb:1 blocking>: ping
#     Client sends to #<Ractor:#2 rac.rb:1 blocking>: pong
#     Server received: pong
#
# It is said that Ractor receives messages via the <em>incoming port</em>, and sends them
# to the <em>outgoing port</em>. Either one can be disabled with Ractor#close_incoming and
# Ractor#close_outgoing respectively.
#
# == Shareable and unshareable objects
#
# When the object is sent to and from the ractor, it is important to understand whether the
# object is shareable or not. Shareable objects are basically those which can be used by several
# threads without compromising thread-safety; e.g. immutable ones. Ractor.shareable? allows to
# check this, and Ractor.make_shareable tries to make object shareable if it is not.
#
#     Ractor.shareable?(1)            #=> true -- numbers and other immutable basic values are
#     Ractor.shareable?('foo')        #=> false, unless the string is frozen due to # freeze_string_literals: true
#     Ractor.shareable?('foo'.freeze) #=> true
#
#     ary = ['hello', 'world']
#     ary.frozen?                 #=> false
#     ary[0].frozen?              #=> false
#     Ractor.make_shareable(ary)
#     ary.frozen?                 #=> true
#     ary[0].frozen?              #=> true
#     ary[1].frozen?              #=> true
#
# When a shareable object is sent (via #send or Ractor.yield), no additional processing happens,
# and it just becomes usable by both ractors. When an unshareable object is sent, it can be
# either _copied_ or _moved_. The first is the default, and it makes the object's full copy by
# deep cloning of non-shareable parts of its structure.
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
# This will output:
#
#     In ractor: 340, 360, 320
#     Outside  : 380, 400, 320
#
# (Note that object id of both array and non-frozen string inside array have changed inside
# the ractor, showing it is different objects. But the second array's element, which is a
# shareable frozen string, has the same object_id.)
#
# Deep cloning of the data may be slow, and sometimes impossible. Alternatively,
# <tt>move: true</tt> may be used on sending. This will <em>move</em> the object to the
# receiving ractor, making it inaccessible for a sending ractor.
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
# Besides frozen objects, shareable objects are instances of Module, Class and Ractor itself. Modules
# and classes, though, can not access instance variables from ractors other than main:
#
#     class C
#       class << self
#         attr_accessor :tricky
#       end
#     end
#
#     C.tricky = 'test'
#
#     r = Ractor.new(C) do |cls|
#       puts "I see #{cls}"
#       puts "I can't see #{cls.tricky}"
#     end
#     r.take
#     # I see C
#     # can not access instance variables of classes/modules from non-main Ractors (RuntimeError)
#
# Ractors can access constants if they are shareable. The main Ractor is the only one that can
# access non-shareable constants.
#
#     GOOD = 'good'.freeze
#     BAD = 'bad'
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
# {Comments syntax}[rdoc-ref:doc/syntax/comments.rdoc] explanation.
#
# == Ractors vs threads
#
# Each ractor creates its own thread. New threads can be created from inside ractor, having the full
# access to its data (and, on CRuby, sharing GVL with other threads of this ractor).
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
# In examples below, sometimes we use the following method to wait till ractors that
# are not currently blocked will finish (or process till next blocking) method.
#
#     def wait
#       sleep(0.1)
#     end
#
# It is **only for demonstration purposes** and shouldn't be used in a real code.
# Most of the times, just #take is used to wait till ractor will finish.
#
class Ractor
  # Create a new Ractor with args and a block.
  #
  # A block (Proc) will be isolated (can't access to outer variables). +self+
  # inside the block will refer to the current Ractor.
  #
  #    r = Ractor.new {puts "Hi, I am #{self.inspect}"}
  #    r.take
  #    # Prints "Hi, I am #<Ractor:#2 test.rb:1 running>"
  #
  # +args+ passed to the method would be propagated to block args by the same rules as
  # objects passed through #send/Ractor.receive: if +args+ are not shareable, they
  # will be copied (via deep cloning, which might be inefficient).
  #
  #    arg = [1, 2, 3]
  #    puts "Passing: #{arg} (##{arg.object_id})"
  #    r = Ractor.new(arg) {|received_arg|
  #     puts "Received: #{received_arg} (##{received_arg.object_id})"
  #    }
  #    r.take
  #    # Prints:
  #    #   Passing: [1, 2, 3] (#280)
  #    #   Received: [1, 2, 3] (#300)
  #
  # Ractor's +name+ can be set for debugging purposes:
  #
  #    r = Ractor.new(name: 'my ractor') {}
  #    p r
  #    #=> #<Ractor:#3 my ractor test.rb:1 terminated>
  #
  def self.new(*args, name: nil, &block)
    b = block # TODO: builtin bug
    raise ArgumentError, "must be called with a block" unless block
    loc = caller_locations(1, 1).first
    loc = "#{loc.path}:#{loc.lineno}"
    __builtin_ractor_create(loc, name, args, b)
  end

  # Returns the currently executing Ractor.
  #
  #   Ractor.current #=> #<Ractor:#1 running>
  def self.current
    __builtin_cexpr! %q{
      rb_ec_ractor_ptr(ec)->self
    }
  end

  # Returns total count of Ractors currently running.
  #
  #    Ractor.count                   #=> 1
  #    r = Ractor.new(name: 'example') {sleep(0.1)}
  #    Ractor.count                   #=> 2 (main + example ractor)
  #    r.take                         # wait till r will finish
  #    Ractor.count                   #=> 1
  def self.count
    __builtin_cexpr! %q{
      ULONG2NUM(GET_VM()->ractor.cnt);
    }
  end

  # call-seq: Ractor.select(*ractors, [yield_value:, move: false]) -> [ractor or symbol, obj]
  #
  # Waits for the first ractor to have something in its outgoing port, reads from this ractor, and
  # returns that ractor and the object received.
  #
  #    r1 = Ractor.new {Ractor.yield 'from 1'}
  #    r2 = Ractor.new {Ractor.yield 'from 2'}
  #
  #    r, obj = Ractor.select(r1, r2)
  #
  #    puts "received #{obj.inspect} from #{r.inspect}"
  #    # Prints: received "from 1" from #<Ractor:#2 test.rb:1 running>
  #
  # If one of the given ractors is the current ractor, and it would be selected, +r+ will contain
  # +:receive+ symbol instead of the ractor object.
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
  #    # Prints: received "to main" from :receive
  #
  # If +yield_value+ is provided, that value may be yielded if another Ractor is calling #take.
  # In this case, the pair <tt>[:yield, nil]</tt> would be returned:
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
  # +move+ boolean flag defines whether yielded value should be copied (default) or moved.
  def self.select(*ractors, yield_value: yield_unspecified = true, move: false)
    raise ArgumentError, 'specify at least one ractor or `yield_value`' if yield_unspecified && ractors.empty?

    __builtin_cstmt! %q{
      const VALUE *rs = RARRAY_CONST_PTR_TRANSIENT(ractors);
      VALUE rv;
      VALUE v = ractor_select(ec, rs, RARRAY_LENINT(ractors),
                              yield_unspecified == Qtrue ? Qundef : yield_value,
                              (bool)RTEST(move) ? true : false, &rv);
      return rb_ary_new_from_args(2, rv, v);
    }
  end

  # Receive an incoming message from the current Ractor's incoming port's queue, which was
  # sent there by #send.
  #
  #     r = Ractor.new do
  #       v1 = Ractor.receive
  #       puts "Received: #{v1}"
  #     end
  #     r.send('message1')
  #     r.take
  #     # Here will be printed: "Received: message1"
  #
  # Alternatively, private instance method +receive+ may be used:
  #
  #     r = Ractor.new do
  #       v1 = receive
  #       puts "Received: #{v1}"
  #     end
  #     r.send('message1')
  #     r.take
  #     # Here will be printed: "Received: message1"
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
  # If close_incoming was called on the ractor, the method raises Ractor::ClosedError:
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

  # Receive only a specific message.
  #
  # Instead of Ractor.receive, Ractor.receive_if can provide a pattern
  # by a block and you can choose the receiving message.
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
  # If the block returns a truthy value, the message will be removed from the incoming queue
  # and return this method with the message.
  # When the block is escaped by break/return/exception and so on, the message also
  # removed from the incoming queue.
  # Otherwise, the messsage remains in the incoming queue and the next received
  # message is checked by the given block.
  #
  # If there is no messages in the incoming queue matching the check, the method will
  # block until such message arrives.
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
  # It means that you should not do any tasks in the block.
  #
  #     Ractor.current << true
  #     Ractor.receive_if{|msg| Ractor.receive}
  #     #=> `receive': can not call receive/receive_if recursively (Ractor::Error)
  #
  def self.receive_if &b
    Primitive.ractor_receive_if b
  end

  private def receive_if &b
    Primitive.ractor_receive_if b
  end

  # Send a message to a Ractor's incoming queue to be consumed by Ractor.receive.
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
  # Attempt to send to ractor which already finished its execution will raise Ractor::ClosedError.
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
  #    # The error would be raised immediately, not when ractor will try to receive
  #
  # If the +obj+ is unshareable, by default it would be copied into ractor by deep cloning.
  # If the <tt>move: true</tt> is passed, object is _moved_ into ractor and becomes
  # inaccessible to sender.
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
  # All references to the object and its parts will become invalid in sender.
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
  # If the object was shareable, <tt>move: true</tt> has no effect on it:
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

  # Send a message to the current ractor's outgoing port to be consumed by #take.
  #
  #    r = Ractor.new {Ractor.yield 'Hello from ractor'}
  #    puts r.take
  #    # Prints: "Hello from ractor"
  #
  # The method is blocking, and will return only when somebody consumes the
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
  # The meaning of +move+ argument is the same as for #send.
  def self.yield(obj, move: false)
    __builtin_cexpr! %q{
      ractor_yield(ec, rb_ec_ractor_ptr(ec), obj, move)
    }
  end

  # Take a message from ractor's outgoing port, which was put there by Ractor.yield or at ractor's
  # finalization.
  #
  #   r = Ractor.new do
  #     Ractor.yield 'explicit yield'
  #     'last value'
  #   end
  #   puts r.take #=> 'explicit yield'
  #   puts r.take #=> 'last value'
  #   puts r.take # Ractor::ClosedError (The outgoing-port is already closed)
  #
  # The fact that the last value is also put to outgoing port means that +take+ can be used
  # as some analog of Thread#join ("just wait till ractor finishes"), but don't forget it
  # will raise if somebody had already consumed everything ractor have produced.
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
  # If an uncaught exception is raised in the Ractor, it is propagated on take as a
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
  # Ractor::ClosedError is a descendant of StopIteration, so the closing of the ractor will break
  # the loops without propagating the error:
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

  def inspect # :nodoc:
    loc  = __builtin_cexpr! %q{RACTOR_PTR(self)->loc}
    name = __builtin_cexpr! %q{RACTOR_PTR(self)->name}
    id   = __builtin_cexpr! %q{INT2FIX(RACTOR_PTR(self)->id)}
    status = __builtin_cexpr! %q{
      rb_str_new2(ractor_status_str(RACTOR_PTR(self)->status_))
    }
    "#<Ractor:##{id}#{name ? ' '+name : ''}#{loc ? " " + loc : ''} #{status}>"
  end

  # The name set in Ractor.new, or +nil+.
  def name
    __builtin_cexpr! %q{RACTOR_PTR(self)->name}
  end

  class RemoteError
    attr_reader :ractor
  end

  # Closes the incoming port and returns its previous state.
  # All further attempts to Ractor.receive in the ractor, and #send to the ractor
  # will fail with Ractor::ClosedError.
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

  # Closes the outgoing port and returns its previous state.
  # All further attempts to Ractor.yield in the ractor, and #take from the ractor
  # will fail with Ractor::ClosedError.
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

  # Checks if the object is shareable by ractors.
  #
  #     Ractor.shareable?(1)            #=> true -- numbers and other immutable basic values are frozen
  #     Ractor.shareable?('foo')        #=> false, unless the string is frozen due to # freeze_string_literals: true
  #     Ractor.shareable?('foo'.freeze) #=> true
  #
  # See also the "Shareable and unshareable objects" section in the Ractor class docs.
  def self.shareable? obj
    __builtin_cexpr! %q{
      rb_ractor_shareable_p(obj) ? Qtrue : Qfalse;
    }
  end

  # Make +obj+ sharable.
  #
  # Basically, traverse referring objects from obj and freeze them.
  #
  # When a sharable object is found in traversing, stop traversing
  # from this shareable object.
  #
  # If +copy+ keyword is +true+, it makes a deep copied object
  # and make it sharable. This is safer option (but it can take more time).
  #
  # Note that the specification and implementation of this method are not
  # matured and can be changed in a future.
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
  #   obj2s.object_id == obj1.object_id   #=> false
  #   obj2s[0].object_id == obj2[0].object_id #=> false
  #
  # See also the "Shareable and unshareable objects" section in the Ractor class docs.
  def self.make_shareable obj, copy: false
    if copy
      __builtin_cexpr! %q{
        rb_ractor_make_copy_shareable(obj);
      }
    else
      __builtin_cexpr! %q{
        rb_ractor_make_shareable(obj);
      }
    end
  end
end
