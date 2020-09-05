# Ractor - Ruby's Actor-like concurrent abstraction

Ractor is designed to provide a parallel execution feature of Ruby without thread-safety concerns.

## Summary

### Multiple Ractors in an interpreter process

You can make multiple Ractors and they run in parallel.

* Ractors run in parallel.
* Interpreter invokes with the first Ractor (called *main Ractor*).
* If main Ractor terminated, all Ractors receive terminate request like Threads (if main thread (first invoked Thread), Ruby interpreter sends all running threads to terminate execution).
* Each Ractor has 1 or more Threads.
  * Threads in a Ractor shares a Ractor-wide global lock like GIL (GVL in MRI terminology), so they can't run in parallel (without releasing GVL explicitly in C-level).
  * The overhead of creating a Ractor is similar to overhead of one Thread creation.

### Limited sharing

Ractors don't share everything, unlike threads.

* Most of objects are *Unshareable objects*, so you don't need to care about thread-safety problem which is caused by sharing.
* Some objects are *Shareable objects*.
  * Immutable objects: frozen object which doesn't refer unshareable-objects.
    * `i = 123`: `i` is an immutable object.
    * `s = "str".freeze`: `s` is an immutable object.
    * `a = [1, [2], 3].freeze`: `a` is not an immutable object because `a` refer unshareable-object `[2]` (which is not frozen).
  * Class/Module objects
  * Special shareable objects
    * Ractor object itself.
    * And more...

### Two-types communication between Ractors

Ractors communicate each other and synchronize the execution by message exchanging between Ractors. There are two message exchange protocol: push type (message passing) and pull type.

* Push type message passing: `Ractor#send(obj)` and `Ractor.receive()` pair.
  * Sender ractor passes the `obj` to receiver Ractor.
  * Sender knows a destination Ractor (the receiver of `r.send(obj)`) and receiver does not know the sender (accept all message from any ractors).
  * Receiver has infinite queue and sender enqueues the message. Sender doesn't block to put message.
  * This type is based on actor model
* Pull type communication: `Ractor.yield(obj)` and `Ractor#take()` pair.
  * Sender ractor declare to yield the `obj` and receiver Ractor take it.
  * Sender doesn't know a destination Ractor and receiver knows the sender (the receiver of `r.take`).
  * Sender or receiver will block if there is no other side.

### Copy & Move semantics to send messages

To send unshareable objects as messages, objects are copied or moved.

* Copy: use deep-copy (like dRuby)
* Move: move membership
  * Sender can not access to the moved object after moving the object.
  * Guarantee that at least only 1 Ractor can access the object.

### Thread-safety

Ractor helps to write a thread-safe program, but we can make thread-unsafe programs with Ractors.

* GOOD: Sharing limitation
  * Most of objects are unshareable, so we can't make data-racy and race-conditional programs.
  * Shareable objects are protected by an interpreter or locking mechanism.
* BAD: Class/Module can violate this assumption
  * To make compatible with old behavior, classes and modules can introduce data-race and so on.
  * Ruby programmer should take care if they modify class/module objects on multi Ractor programs.
* BAD: Ractor can't solve all thread-safety problems
  * There are several blocking operations (waiting send, waiting yield and waiting take) so you can make a program which has dead-lock and live-lock issues.
  * Some kind of shareable objects can introduce transactions (STM, for example). However, misusing transactions will generate inconsistent state.

Without Ractor, we need to trace all of state-mutations to debug thread-safety issues.
With Ractor, you can concentrate to suspicious 

## Creation and termination

### `Ractor.new`

* `Ractor.new do expr end` generates another Ractor.

```ruby
# Ractor.new with a block creates new Ractor
r = Ractor.new do
  # This block will be run in parallel
end

# You can name a Ractor with `name:` argument.
r = Ractor.new name: 'test-name' do
end

# and Ractor#name returns its name.
r.name #=> 'test-name'
```

### Given block isolation

The Ractor execute given `expr` in a given block.
Given block will be isolated from outer scope by `Proc#isolate`.

```ruby
# To prevent sharing unshareable objects between ractors, 
# block outer-variables, `self` and other information are isolated.
# Given block will be isolated by `Proc#isolate` method.
# `Proc#isolate` is called at Ractor creation timing (`Ractor.new` is called)
# and it can cause an error if block accesses outer variables.

begin
  a = true
  r = Ractor.new do
    a #=> ArgumentError because this block accesses `a`.
  end
  r.take # see later
rescue ArgumentError
end
```

* The `self` of the given block is `Ractor` object itself.

```ruby
r = Ractor.new do
  self.object_id
end
r.take == self.object_id #=> false
```

Passed arguments to `Ractor.new()` becomes block parameters for the given block. However, an interpreter does not pass the parameter object references, but send as messages (see bellow for details).

```ruby
r = Ractor.new 'ok' do |msg|
  msg #=> 'ok'
end
r.take #=> 'ok'
```

```ruby
# almost similar to the last example
r = Ractor.new do
  msg = Ractor.recv
  msg
end
r.send 'ok'
r.take #=> 'ok'
```

### An execution result of given block

Return value of the given block becomes an outgoing message (see below for details).

```ruby
r = Ractor.new do
  'ok'
end
r.take #=> `ok`
```

```ruby
# almost similar to the last example
r = Ractor.new do
  Ractor.yield 'ok'
end
r.take #=> 'ok'
```

Error in the given block will be propagated to the receiver of an outgoing message.

```ruby
r = Ractor.new do
  raise 'ok' # exception will be transferred receiver
end

begin
  r.take
rescue Ractor::RemoteError => e
  e.cause.class   #=> RuntimeError
  e.cause.message #=> 'ok'
  e.ractor        #=> r
end
```

## Communication between Ractors

Communication between Ractors is achieved by sending and receiving messages.

* (1) Message sending/receiving
  * (1-1) push type send/recv (sender knows receiver). similar to the Actor model.
  * (1-2) pull type yield/take (receiver knows sender).
* (2) Using shareable container objects (not implemented yet)

Users can control blocking on (1), but should not control on (2) (only manage as critical section).

* (1-1) send/recv (push type)
  * `Ractor#send(obj)` (`Ractor#<<(obj)` is an aliases) send a message to the Ractor's incoming port. Incoming port is connected to the infinite size incoming queue so `Ractor#send` will never block.
  * `Ractor.recv` dequeue a message from own incoming queue. If the incoming queue is empty, `Ractor.recv` calling will block.
* (1-2) yield/take (pull type)
  * `Ractor.yield(obj)` send an message to a Ractor which are calling `Ractor#take` via outgoing port . If no Ractors are waiting for it, the `Ractor.yield(obj)` will block. If multiple Ractors are waiting for `Ractor.yield(obj)`, only one Ractor can receive the message.
  * `Ractor#take` receives a message which is waiting by `Ractor.yield(obj)` method from the specified Ractor. If the Ractor does not call `Ractor.yield` yet, the `Ractor#take` call will block.
* `Ractor.select()` can wait for the success of `take`, `yield` and `recv`.
* You can close the incoming port or outgoing port.
  * You can close then with `Ractor#close_incoming` and `Ractor#close_outgoing`.
  * If the incoming port is closed for a Ractor, you can't `send` to the Ractor. If `Ractor.recv` is blocked for the closed incoming port, then it will raise an exception.
  * If the outgoing port is closed for a Ractor, you can't call `Ractor#take` and `Ractor.yield` on the Ractor. If `Ractor#take` is blocked for the Ractor, then it will raise an exception.
  * When a Ractor is terminated, the Ractor's ports are closed.
* There are 3 methods to send an object as a message
  * (1) Send a reference: Send a shareable object, send only a reference to the object (fast)
  * (2) Copy an object: Send an unshareable object by copying deeply and send copied object (slow). Note that you can not send an object which is not support deep copy. Current implementation uses Marshal protocol to get deep copy.
  * (3) Move an object: Send an unshareable object reference with a membership. Sender Ractor can not access moved objects anymore (raise an exception). Current implementation makes new object as a moved object for receiver Ractor and copy references of sending object to moved object.
  * You can choose "Copy" and "Send" as a keyword for `Ractor#send(obj)` and `Ractor.yield(obj)` (default is "Copy").

### Sending/Receiving ports

Each Ractor has _incoming-port_ and _outgoing-port_. Incoming-port is connected to the infinite sized incoming queue.

```
                  Ractor r
                 +-------------------------------------------+
                 | incoming                         outgoing |
                 | port                                 port |
   r.send(obj) ->*->[incoming queue]     Ractor.yield(obj) ->*-> r.take
                 |                |                          |
                 |                v                          |
                 |           Ractor.recv                     |
                 +-------------------------------------------+


Connection example: r2.send obj on r1、Ractor.recv on r2
  +----+     +----+
  * r1 |-----* r2 *
  +----+     +----+


Connection example: Ractor.yield(obj) on r1, r1.take on r2
  +----+     +----+
  * r1 *------ r2 *
  +----+     +----+

Connection example: Ractor.yield(obj) on r1 and r2,
                    and waiting for both simultaneously by Ractor.select(r1, r2)

  +----+
  * r1 *------+
  +----+      |
              +----- Ractor.select(r1, r2)
  +----+      |
  * r2 *------|
  +----+
```

```ruby
  r = Ractor.new do
    msg = Ractor.recv # Receive from r's incoming queue
    msg # send back msg as block return value
  end
  r.send 'ok' # Send 'ok' to r's incoming port -> incoming queue
  r.take      # Receive from r's outgoing port
```

```ruby
  # Actual argument 'ok' for `Ractor.new()` will be send to created Ractor. 
  r = Ractor.new 'ok' do |msg|
    # Values for formal parameters will be received from incoming queue.
    # Similar to: msg = Ractor.recv

    msg # Return value of the given block will be sent via outgoing port
  end

  # receive from the r's outgoing port.
  r.take #=> `ok`
```

### Wait for multiple Ractors with `Ractor.select`

You can wait multiple Ractor's `yield` with `Ractor.select(*ractors)`.
The return value of `Ractor.select()` is `[r, msg]` where `r` is yielding Ractor and `msg` is yielded message.

Wait for a single ractor (same as `Ractor.take`):

```ruby
r1 = Ractor.new{'r1'}

r, obj = Ractor.select(r1)
r == r1 and obj == 'r1' #=> true
```

Wait for two ractors:

```ruby
r1 = Ractor.new{'r1'}
r2 = Ractor.new{'r2'}
rs = [r1, r2]
as = []

# Wait for r1 or r2's Ractor.yield
r, obj = Ractor.select(*rs)
rs.delete(r)
as << obj

# Second try (rs only contain not-closed ractors)
r, obj = Ractor.select(*rs)
rs.delete(r)
as << obj
as.sort == ['r1', 'r2'] #=> true
```

Complex example:

```ruby
  pipe = Ractor.new do
    loop do
      Ractor.yield Ractor.recv
    end
  end

  RN = 10
  rs = RN.times.map{|i|
    Ractor.new pipe, i do |pipe, i|
      msg = pipe.take
      msg # ping-pong
    end
  }
  RN.times{|i|
    pipe << i
  }
  RN.times.map{
    r, n = Ractor.select(*rs)
    rs.delete r
    n
  }.sort #=> [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
```

Multiple Ractors can send to one Ractor.

```ruby
# Create 10 ractors and they send objects to pipe ractor.
# pipe ractor yield received objects

  pipe = Ractor.new do
    loop do
      Ractor.yield Ractor.recv
    end
  end

  RN = 10
  rs = RN.times.map{|i|
    Ractor.new pipe, i do |pipe, i|
      pipe << i
    end
  }

  RN.times.map{
    pipe.take
  }.sort #=> [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
```

TODO: Current `Ractor.select()` has same issue of `select(2)`, so this interface should be refined.

TODO: `select` syntax of go-language uses round-robin technique to make fair scheduling. Now `Ractor.select()` doesn't use it.

### Closing Ractor's ports

* `Ractor#close_incoming/outgoing` close incoming/outgoing ports (similar to `Queue#close`).
* `Ractor#close_incoming`
  * `r.send(obj) ` where `r`'s incoming port is closed, will raise an exception.
  * When the incoming queue is empty and incoming port is closed, `Ractor.recv` raise an exception. If incoming queue is not empty, it dequeues an object.
* `Ractor#close_outgoing`
  * `Ractor.yield` on a Ractor which closed the outgoing port, it will raise an exception.
  * `Ractor#take` for a Ractor which closed the outgoing port, it will raise an exception. If `Ractor#take` is blocking, it will raise an exception.
* When a Ractor terminates, the ports are closed automatically.
  * Return value of the Ractor's block will be yield as `Ractor.yield(ret_val)`, even if the implementation terminate the based native thread.


Example (try to take from closed Ractor):

```ruby
  r = Ractor.new do
    'finish'
  end
  r.take # success (will return 'finish')
  begin
    o = r.take # try to take from closed Ractor
  rescue Ractor::ClosedError
    'ok'
  else
    "ng: #{o}"
  end
```

Example (try to send to closed (terminated) Ractor):

```ruby
  r = Ractor.new do
  end

  r.take # wait terminate

  begin
    r.send(1)
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
```

When multiple Ractors waiting for `Ractor.yield()`, `Ractor#close_outgoing` will cancel all blocking by raise an exception (`ClosedError`).

### Send a message by copying

`Ractor#send(obj)` or `Ractor.yield(obj)` copy `obj` deeply if `obj` is an unshareable object.

```ruby
obj = 'str'.dup
r = Ractor.new obj do |msg|
  # return received msg's object_id
  msg.object_id
end
  
obj.object_id == r.take #=> false
```

Current implementation uses Marshal protocol (similar to dRuby). We can not send Marshal unsupported objects.

```ruby
obj = Thread.new{}
begin
  Ractor.new obj do |msg|
    msg
  end
rescue TypeError => e
  e.message #=> no _dump_data is defined for class Thread
else
  'ng' # unreachable here
end
```

### Send a message by moving

`Ractor#send(obj, move: true)` or `Ractor.yield(obj, move: true)` move `obj` to the destination Ractor.
If the source Ractor touches the moved object (for example, call the method like `obj.foo()`), it will be an error.

```ruby
# move with Ractor#send
r = Ractor.new do
  obj = Ractor.recv
  obj << ' world'
end

str = 'hello'
r.send str, move: true
modified = r.take #=> 'hello world'

# str is moved, and accessing str from this Ractor is prohibited

begin
  # Error because it touches moved str.
  str << ' exception' # raise Ractor::MovedError
rescue Ractor::MovedError
  modified #=> 'hello world'
else
  raise 'unreachable'
end
```

```ruby
  # move with Ractor.yield
  r = Ractor.new do
    obj = 'hello'
    Ractor.yield obj, move: true
    obj << 'world'  # raise Ractor::MovedError
  end

  str = r.take
  begin
    r.take 
  rescue Ractor::RemoteError
    p str #=> "hello"
  end
```

Now only `T_FILE`, `T_STRING` and `T_ARRAY` objects are supported.

* `T_FILE` (`IO`, `File`): support to send accepted socket etc.
* `T_STRING` (`String`): support to send a huge string without copying (fast).
* `T_ARRAY` (`Array'): support to send a huge Array without re-allocating the array's buffer. However, all of referred objects from the array should be moved, so it is not so fast.

To achieve the access prohibition for moved objects, _class replacement_ technique is used to implement it. 

### Shareable objects

The following objects are shareable.

* Immutable objects
  * Small integers, some symbols, `true`, `false`, `nil` (a.k.a. `SPECIAL_CONST_P()` objects in internal)
  * Frozen native objects
    * Numeric objects: `Float`, `Complex`, `Rational`, big integers (`T_BIGNUM` in internal)
    * All Symbols.
  * Frozen `String` and `Regexp` objects (which does not have instance variables)
  * In future, "Immutable" objects (frozen and only refer shareable objects) will be supported (TODO: introduce an `immutable` flag for objects?)
* Class, Module objects (`T_CLASS`, `T_MODULE` and `T_ICLASS` in internal)
* `Ractor` and other objects which care about synchronization.

Implementation: Now shareable objects (`RVALUE`) have `FL_SHAREABLE` flag. This flag can be added lazily.

```ruby
  r = Ractor.new do
    while v = Ractor.recv
      Ractor.yield v
    end
  end

  class C
  end

  shareable_objects = [1, :sym, 'xyzzy'.to_sym, 'frozen'.freeze, 1+2r, 3+4i, /regexp/, C]

  shareable_objects.map{|o|
    r << o
    o2 = r.take
    [o, o.object_id == o2.object_id]
  }
  #=> [[1, true], [:sym, true], [:xyzzy, true], [\"frozen\", true], [(3/1), true], [(3+4i), true], [/regexp/, true], [C, true]]

  unshareable_objects = ['mutable str'.dup, [:array], {hash: true}].map{|o|
    r << o
    o2 = r.take
    [o, o.object_id == o2.object_id]
  }
  #+> "[[\"mutable str\", false], [[:array], false], [{:hash=>true}, false]]]"
```

## Language changes to isolate unshareable objects between Ractors

To isolate unshareable objects between Ractors, we introduced additional language semantics on multi-Ractor.

Note that without using Ractors, these additional semantics is not needed (100% compatible with Ruby 2).

### Global variables

Only main Ractor (a Ractor created at starting of interpreter) can access global variables.

```ruby
  $gv = 1
  r = Ractor.new do
    $gv
  end

  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message #=> 'can not access global variables from non-main Ractors'
  end
```

### Instance variables of shareable objects

Only main Ractor can access instance variables of shareable objects.

```ruby
  class C
    @iv = 'str'
  end

  r = Ractor.new do
    class C
      p @iv
    end
  end


  begin
    r.take
  rescue => e
    e.class #=> RuntimeError
  end
```

```ruby
  shared = Ractor.new{}
  shared.instance_variable_set(:@iv, 'str')

  r = Ractor.new shared do |shared|
    p shared.instance_variable_get(:@iv)
  end

  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message #=> can not access instance variables of shareable objects from non-main Ractors
  end
```

Note that instance variables for class/module objects are also prohibited on Ractors.

### Class variables

Only main Ractor can access class variables.

```ruby
  class C
    @@cv = 'str'
  end

  r = Ractor.new do
    class C
      p @@cv
    end
  end


  begin
    r.take
  rescue => e
    e.class #=> RuntimeError
  end
```

### Constants

Only main Ractor can read constants which refer to the unshareable object.

```ruby
  class C
    CONST = 'str'
  end
  r = Ractor.new do
    C::CONST
  end
  begin
    r.take
  rescue => e
    e.class #=> NameError
  end
```

Only main Ractor can define constants which refer to the unshareable object.

```ruby
  class C
  end
  r = Ractor.new do
    C::CONST = 'str'
  end
  begin
    r.take
  rescue => e
    e.class #=> NameError
  end
```

## Implementation note

* Each Ractor has its own thread, it means each Ractor has at least 1 native thread.
* Each Ractor has its own ID (`rb_ractor_t::id`).
  * On debug mode, all unshareable objects are labeled with current Ractor's id, and it is checked to detect unshareable object leak (access an object from different Ractor) in VM.

## Examples

### Traditional Ring example in Actor-model

```ruby
RN = 1000
CR = Ractor.current

r = Ractor.new do
  p Ractor.recv
  CR << :fin
end

RN.times{
  Ractor.new r do |next_r|
    next_r << Ractor.recv
  end
}

p :setup_ok
r << 1
p Ractor.recv
```

### Fork-join

```ruby
def fib n
  if n < 2
    1
  else
    fib(n-2) + fib(n-1)
  end
end

RN = 10
rs = (1..RN).map do |i|
  Ractor.new i do |i|
    [i, fib(i)]
  end
end

until rs.empty?
  r, v = Ractor.select(*rs)
  rs.delete r
  p answer: v
end
```

### Worker pool

```ruby
require 'prime'

pipe = Ractor.new do
  loop do
    Ractor.yield Ractor.recv
  end
end

N = 1000
RN = 10
workers = (1..RN).map do
  Ractor.new pipe do |pipe|
    while n = pipe.take
      Ractor.yield [n, n.prime?]
    end
  end
end

(1..N).each{|i|
  pipe << i
}

pp (1..N).map{
  _r, (n, b) = Ractor.select(*workers)
  [n, b]
}.sort_by{|(n, b)| n}
```

### Pipeline

```ruby
# pipeline with yield/take
r1 = Ractor.new do
  'r1'
end

r2 = Ractor.new r1 do |r1|
  r1.take + 'r2'
end

r3 = Ractor.new r2 do |r2|
  r2.take + 'r3'
end

p r3.take #=> 'r1r2r3'
```

```ruby
# pipeline with send/recv

r3 = Ractor.new Ractor.current do |cr|
  cr.send Ractor.recv + 'r3'
end

r2 = Ractor.new r3 do |r3|
  r3.send Ractor.recv + 'r2'
end

r1 = Ractor.new r2 do |r2|
  r2.send Ractor.recv + 'r1'
end

r1 << 'r0'
p Ractor.recv #=> "r0r1r2r3"
```

### Supervise

```ruby
# ring example again

r = Ractor.current
(1..10).map{|i|
  r = Ractor.new r, i do |r, i|
    r.send Ractor.recv + "r#{i}"
  end
}

r.send "r0"
p Ractor.recv #=> "r0r10r9r8r7r6r5r4r3r2r1"
```

```ruby
# ring example with an error

r = Ractor.current
rs = (1..10).map{|i|
  r = Ractor.new r, i do |r, i|
    loop do
      msg = Ractor.recv
      raise if /e/ =~ msg
      r.send msg + "r#{i}"
    end
  end
}

r.send "r0"
p Ractor.recv #=> "r0r10r9r8r7r6r5r4r3r2r1"
r.send "r0"
p Ractor.select(*rs, Ractor.current) #=> [:recv, "r0r10r9r8r7r6r5r4r3r2r1"]
[:recv, "r0r10r9r8r7r6r5r4r3r2r1"]
r.send "e0"
p Ractor.select(*rs, Ractor.current)
#=>
#<Thread:0x000056262de28bd8 run> terminated with exception (report_on_exception is true):
Traceback (most recent call last):
        2: from /home/ko1/src/ruby/trunk/test.rb:7:in `block (2 levels) in <main>'
        1: from /home/ko1/src/ruby/trunk/test.rb:7:in `loop'
/home/ko1/src/ruby/trunk/test.rb:9:in `block (3 levels) in <main>': unhandled exception
Traceback (most recent call last):
        2: from /home/ko1/src/ruby/trunk/test.rb:7:in `block (2 levels) in <main>'
        1: from /home/ko1/src/ruby/trunk/test.rb:7:in `loop'
/home/ko1/src/ruby/trunk/test.rb:9:in `block (3 levels) in <main>': unhandled exception
        1: from /home/ko1/src/ruby/trunk/test.rb:21:in `<main>'
<internal:ractor>:69:in `select': thrown by remote Ractor. (Ractor::RemoteError)
```

```ruby
# resend non-error message

r = Ractor.current
rs = (1..10).map{|i|
  r = Ractor.new r, i do |r, i|
    loop do
      msg = Ractor.recv
      raise if /e/ =~ msg
      r.send msg + "r#{i}"
    end
  end
}

r.send "r0"
p Ractor.recv #=> "r0r10r9r8r7r6r5r4r3r2r1"
r.send "r0"
p Ractor.select(*rs, Ractor.current)
[:recv, "r0r10r9r8r7r6r5r4r3r2r1"]
msg = 'e0'
begin
  r.send msg
  p Ractor.select(*rs, Ractor.current)
rescue Ractor::RemoteError
  msg = 'r0'
  retry
end

#=> <internal:ractor>:100:in `send': The incoming-port is already closed (Ractor::ClosedError)
# because r == r[-1] is terminated.
```

```ruby
# ring example with supervisor and re-start

def make_ractor r, i
  Ractor.new r, i do |r, i|
    loop do
      msg = Ractor.recv
      raise if /e/ =~ msg
      r.send msg + "r#{i}"
    end
  end
end

r = Ractor.current
rs = (1..10).map{|i|
  r = make_ractor(r, i)
}

msg = 'e0' # error causing message
begin
  r.send msg
  p Ractor.select(*rs, Ractor.current)
rescue Ractor::RemoteError
  r = rs[-1] = make_ractor(rs[-2], rs.size-1)
  msg = 'x0'
  retry
end

#=> [:recv, "x0r9r9r8r7r6r5r4r3r2r1"]
```
