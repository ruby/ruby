# Ractor - Ruby's Actor-like concurrent abstraction

Ractor is designed to provide a parallel execution feature of Ruby without thread-safety concerns.

## Summary

### Multiple Ractors in an interpreter process

You can make multiple Ractors and they run in parallel.

* `Ractor.new{ expr }` creates a new Ractor and `expr` is run in parallel on a parallel computer.
* Interpreter invokes with the first Ractor (called *main Ractor*).
* If main Ractor terminated, all Ractors receive terminate request like Threads (if main thread (first invoked Thread), Ruby interpreter sends all running threads to terminate execution).
* Each Ractor has 1 or more Threads.
  * Threads in a Ractor shares a Ractor-wide global lock like GIL (GVL in MRI terminology), so they can't run in parallel (without releasing GVL explicitly in C-level). Threads in different ractors run in parallel.
  * The overhead of creating a Ractor is similar to overhead of one Thread creation.

### Limited sharing between multiple ractors

Ractors don't share everything, unlike threads.

* Most objects are *Unshareable objects*, so you don't need to care about thread-safety problems which are caused by sharing.
* Some objects are *Shareable objects*.
  * Immutable objects: frozen objects which don't refer to unshareable-objects.
    * `i = 123`: `i` is an immutable object.
    * `s = "str".freeze`: `s` is an immutable object.
    * `a = [1, [2], 3].freeze`: `a` is not an immutable object because `a` refers unshareable-object `[2]` (which is not frozen).
    * `h = {c: Object}.freeze`: `h` is an immutable object because `h` refers Symbol `:c` and shareable `Object` class object which is not frozen.
  * Class/Module objects
  * Special shareable objects
    * Ractor object itself.
    * And more...

### Two-types communication between Ractors

Ractors communicate with each other and synchronize the execution by message exchanging between Ractors. There are two message exchange protocols: push type (message passing) and pull type.

* Push type message passing: `Ractor#send(obj)` and `Ractor.receive()` pair.
  * Sender ractor passes the `obj` to the ractor `r` by `r.send(obj)` and receiver ractor receives the message with `Ractor.receive`.
  * Sender knows the destination Ractor `r` and the receiver does not know the sender (accept all messages from any ractors).
  * Receiver has infinite queue and sender enqueues the message. Sender doesn't block to put message into this queue.
  * This type of message exchanging is employed by many other Actor-based languages.
  * `Ractor.receive_if{ filter_expr }` is a variant of `Ractor.receive` to select a message.
* Pull type communication: `Ractor.yield(obj)` and `Ractor#take()` pair.
  * Sender ractor declare to yield the `obj` by `Ractor.yield(obj)` and receiver Ractor take it with `r.take`.
  * Sender doesn't know a destination Ractor and receiver knows the sender Ractor `r`.
  * Sender or receiver will block if there is no other side.

### Copy & Move semantics to send messages

To send unshareable objects as messages, objects are copied or moved.

* Copy: use deep-copy.
* Move: move membership.
  * Sender can not access the moved object after moving the object.
  * Guarantee that at least only 1 Ractor can access the object.

### Thread-safety

Ractor helps to write a thread-safe concurrent program, but we can make thread-unsafe programs with Ractors.

* GOOD: Sharing limitation
  * Most objects are unshareable, so we can't make data-racy and race-conditional programs.
  * Shareable objects are protected by an interpreter or locking mechanism.
* BAD: Class/Module can violate this assumption
  * To make it compatible with old behavior, classes and modules can introduce data-race and so on.
  * Ruby programmers should take care if they modify class/module objects on multi Ractor programs.
* BAD: Ractor can't solve all thread-safety problems
  * There are several blocking operations (waiting send, waiting yield and waiting take) so you can make a program which has dead-lock and live-lock issues.
  * Some kind of shareable objects can introduce transactions (STM, for example). However, misusing transactions will generate inconsistent state.

Without Ractor, we need to trace all state-mutations to debug thread-safety issues.
With Ractor, you can concentrate on suspicious code which are shared with Ractors.

## Creation and termination

### `Ractor.new`

* `Ractor.new{ expr }` generates another Ractor.

```ruby
# Ractor.new with a block creates new Ractor
r = Ractor.new do
  # This block will be run in parallel with other ractors
end

# You can name a Ractor with `name:` argument.
r = Ractor.new name: 'test-name' do
end

# and Ractor#name returns its name.
r.name #=> 'test-name'
```

### Given block isolation

The Ractor executes given `expr` in a given block.
Given block will be isolated from outer scope by the `Proc#isolate` method (not exposed yet for Ruby users). To prevent sharing unshareable objects between ractors, block outer-variables, `self` and other information are isolated.

`Proc#isolate` is called at Ractor creation time (when `Ractor.new` is called). If given Proc object is not able to isolate because of outer variables and so on, an error will be raised.

```ruby
begin
  a = true
  r = Ractor.new do
    a #=> ArgumentError because this block accesses `a`.
  end
  r.take # see later
rescue ArgumentError
end
```

* The `self` of the given block is the `Ractor` object itself.

```ruby
r = Ractor.new do
  p self.class #=> Ractor
  self.object_id
end
r.take == self.object_id #=> false
```

Passed arguments to `Ractor.new()` becomes block parameters for the given block. However, an interpreter does not pass the parameter object references, but send them as messages (see below for details).

```ruby
r = Ractor.new 'ok' do |msg|
  msg #=> 'ok'
end
r.take #=> 'ok'
```

```ruby
# almost similar to the last example
r = Ractor.new do
  msg = Ractor.receive
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
  raise 'ok' # exception will be transferred to the receiver
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

Communication between Ractors is achieved by sending and receiving messages. There are two ways to communicate with each other.

* (1) Message sending/receiving
  * (1-1) push type send/receive (sender knows receiver). Similar to the Actor model.
  * (1-2) pull type yield/take (receiver knows sender).
* (2) Using shareable container objects
  * Ractor::TVar gem ([ko1/ractor-tvar](https://github.com/ko1/ractor-tvar))
  * more?

Users can control program execution timing with (1), but should not control with (2) (only manage as critical section).

For message sending and receiving, there are two types of APIs: push type and pull type.

* (1-1) send/receive (push type)
  * `Ractor#send(obj)` (`Ractor#<<(obj)` is an alias) send a message to the Ractor's incoming port. Incoming port is connected to the infinite size incoming queue so `Ractor#send` will never block.
  * `Ractor.receive` dequeue a message from its own incoming queue. If the incoming queue is empty, `Ractor.receive` calling will block.
  * `Ractor.receive_if{|msg| filter_expr }` is variant of `Ractor.receive`. `receive_if` only receives a message which `filter_expr` is true (So `Ractor.receive` is the same as `Ractor.receive_if{ true }`.
* (1-2) yield/take (pull type)
  * `Ractor.yield(obj)` send an message to a Ractor which are calling `Ractor#take` via outgoing port . If no Ractors are waiting for it, the `Ractor.yield(obj)` will block. If multiple Ractors are waiting for `Ractor.yield(obj)`, only one Ractor can receive the message.
  * `Ractor#take` receives a message which is waiting by `Ractor.yield(obj)` method from the specified Ractor. If the Ractor does not call `Ractor.yield` yet, the `Ractor#take` call will block.
* `Ractor.select()` can wait for the success of `take`, `yield` and `receive`.
* You can close the incoming port or outgoing port.
  * You can close then with `Ractor#close_incoming` and `Ractor#close_outgoing`.
  * If the incoming port is closed for a Ractor, you can't `send` to the Ractor. If `Ractor.receive` is blocked for the closed incoming port, then it will raise an exception.
  * If the outgoing port is closed for a Ractor, you can't call `Ractor#take` and `Ractor.yield` on the Ractor. If ractors are blocking by `Ractor#take` or `Ractor.yield`, closing outgoing port will raise an exception on these blocking ractors.
  * When a Ractor is terminated, the Ractor's ports are closed.
* There are 3 ways to send an object as a message
  * (1) Send a reference: Sending a shareable object, send only a reference to the object (fast)
  * (2) Copy an object: Sending an unshareable object by copying an object deeply (slow). Note that you can not send an object which does not support deep copy. Some `T_DATA` objects (objects whose class is defined in a C extension, such as `StringIO`) are not supported.
  * (3) Move an object: Sending an unshareable object reference with a membership. Sender Ractor can not access moved objects anymore (raise an exception) after moving it. Current implementation makes new object as a moved object for receiver Ractor and copies references of sending object to moved object. `T_DATA` objects are not supported.
  * You can choose "Copy" and "Move" by the `move:` keyword, `Ractor#send(obj, move: true/false)` and `Ractor.yield(obj, move: true/false)` (default is `false` (COPY)).

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
                 |           Ractor.receive                  |
                 +-------------------------------------------+


Connection example: r2.send obj on r1、Ractor.receive on r2
  +----+     +----+
  * r1 |---->* r2 *
  +----+     +----+


Connection example: Ractor.yield(obj) on r1, r1.take on r2
  +----+     +----+
  * r1 *---->- r2 *
  +----+     +----+

Connection example: Ractor.yield(obj) on r1 and r2,
                    and waiting for both simultaneously by Ractor.select(r1, r2)

  +----+
  * r1 *------+
  +----+      |
              +----> Ractor.select(r1, r2)
  +----+      |
  * r2 *------|
  +----+
```

```ruby
r = Ractor.new do
  msg = Ractor.receive # Receive from r's incoming queue
  msg # send back msg as block return value
end
r.send 'ok' # Send 'ok' to r's incoming port -> incoming queue
r.take      # Receive from r's outgoing port
```

The last example shows the following ractor network.

```
  +------+        +---+
  * main |------> * r *---+
  +------+        +---+   |
      ^                   |
      +-------------------+
```

And this code can be simplified by using an argument for `Ractor.new`.

```ruby
# Actual argument 'ok' for `Ractor.new()` will be sent to created Ractor.
r = Ractor.new 'ok' do |msg|
  # Values for formal parameters will be received from incoming queue.
  # Similar to: msg = Ractor.receive

  msg # Return value of the given block will be sent via outgoing port
end

# receive from the r's outgoing port.
r.take #=> `ok`
```

### Return value of a block for `Ractor.new`

As already explained, the return value of `Ractor.new` (an evaluated value of `expr` in `Ractor.new{ expr }`) can be taken by `Ractor#take`.

```ruby
Ractor.new{ 42 }.take #=> 42
```

When the block return value is available, the Ractor is dead so that no ractors except taken Ractor can touch the return value, so any values can be sent with this communication path without any modification.

```ruby
r = Ractor.new do
  a = "hello"
  binding
end

r.take.eval("p a") #=> "hello" (other communication path can not send a Binding object directly)
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
    Ractor.yield Ractor.receive
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
    Ractor.yield Ractor.receive
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

TODO: Current `Ractor.select()` has the same issue of `select(2)`, so this interface should be refined.

TODO: `select` syntax of go-language uses round-robin technique to make fair scheduling. Now `Ractor.select()` doesn't use it.

### Closing Ractor's ports

* `Ractor#close_incoming/outgoing` close incoming/outgoing ports (similar to `Queue#close`).
* `Ractor#close_incoming`
  * `r.send(obj)` where `r`'s incoming port is closed, will raise an exception.
  * When the incoming queue is empty and incoming port is closed, `Ractor.receive` raises an exception. If the incoming queue is not empty, it dequeues an object without exceptions.
* `Ractor#close_outgoing`
  * `Ractor.yield` on a Ractor which closed the outgoing port, it will raise an exception.
  * `Ractor#take` for a Ractor which closed the outgoing port, it will raise an exception. If `Ractor#take` is blocking, it will raise an exception.
* When a Ractor terminates, the ports are closed automatically.
  * Return value of the Ractor's block will be yielded as `Ractor.yield(ret_val)`, even if the implementation terminates the based native thread.

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

When multiple Ractors are waiting for `Ractor.yield()`, `Ractor#close_outgoing` will cancel all blocking by raising an exception (`ClosedError`).

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

Some objects are not supported to copy the value, and raise an exception.

```ruby
obj = Thread.new{}
begin
  Ractor.new obj do |msg|
    msg
  end
rescue TypeError => e
  e.message #=> #<TypeError: allocator undefined for Thread>
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
  obj = Ractor.receive
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

Some objects are not supported to move, and an exception will be raised.

```ruby
r = Ractor.new do
  Ractor.receive
end

r.send(Thread.new{}, move: true) #=> allocator undefined for Thread (TypeError)
```

To achieve the access prohibition for moved objects, _class replacement_ technique is used to implement it.

### Shareable objects

The following objects are shareable.

* Immutable objects
  * Small integers, some symbols, `true`, `false`, `nil` (a.k.a. `SPECIAL_CONST_P()` objects in internal)
  * Frozen native objects
    * Numeric objects: `Float`, `Complex`, `Rational`, big integers (`T_BIGNUM` in internal)
    * All Symbols.
  * Frozen `String` and `Regexp` objects (their instance variables should refer only shareable objects)
* Class, Module objects (`T_CLASS`, `T_MODULE` and `T_ICLASS` in internal)
* `Ractor` and other special objects which care about synchronization.

Implementation: Now shareable objects (`RVALUE`) have `FL_SHAREABLE` flag. This flag can be added lazily.

To make shareable objects, `Ractor.make_shareable(obj)` method is provided. In this case, try to make sharaeble by freezing `obj` and recursively traversable objects. This method accepts `copy:` keyword (default value is false).`Ractor.make_shareable(obj, copy: true)` tries to make a deep copy of `obj` and make the copied object shareable.

## Language changes to isolate unshareable objects between Ractors

To isolate unshareable objects between Ractors, we introduced additional language semantics on multi-Ractor Ruby programs.

Note that without using Ractors, these additional semantics is not needed (100% compatible with Ruby 2).

### Global variables

Only the main Ractor (a Ractor created at starting of interpreter) can access global variables.

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

Note that some special global variables are ractor-local, like `$stdin`, `$stdout`, `$stderr`. See [[Bug #17268]](https://bugs.ruby-lang.org/issues/17268) for more details.

### Instance variables of shareable objects

Instance variables of classes/modules can be get from non-main Ractors if the referring values are shareable objects.

```ruby
class C
  @iv = 1
end

p Ractor.new do
  class C
     @iv
  end
end.take #=> 1
```

Otherwise, only the main Ractor can access instance variables of shareable objects.

```ruby
class C
  @iv = [] # unshareable object
end

Ractor.new do
  class C
    begin
      p @iv
    rescue Ractor::IsolationError
      p $!.message
      #=> "can not get unshareable values from instance variables of classes/modules from non-main Ractors"
    end

    begin
      @iv = 42
    rescue Ractor::IsolationError
      p $!.message
      #=> "can not set instance variables of classes/modules by non-main Ractors"
    end
  end
end.take
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
  e.cause.message #=> can not access instance variables of shareable objects from non-main Ractors (Ractor::IsolationError)
end
```

Note that instance variables for class/module objects are also prohibited on Ractors.

### Class variables

Only the main Ractor can access class variables.

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
  e.class #=> Ractor::IsolationError
end
```

### Constants

Only the main Ractor can read constants which refer to the unshareable object.

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
  e.class #=> Ractor::IsolationError
end
```

Only the main Ractor can define constants which refer to the unshareable object.

```ruby
class C
end
r = Ractor.new do
  C::CONST = 'str'
end
begin
  r.take
rescue => e
  e.class #=> Ractor::IsolationError
end
```

To make multi-ractor supported library, the constants should only refer shareable objects.

```ruby
TABLE = {a: 'ko1', b: 'ko2', c: 'ko3'}
```

In this case, `TABLE` references an unshareable Hash object. So that other ractors can not refer `TABLE` constant. To make it shareable, we can use `Ractor.make_shareable()` like that.

```ruby
TABLE = Ractor.make_shareable( {a: 'ko1', b: 'ko2', c: 'ko3'} )
```

To make it easy, Ruby 3.0 introduced new `shareable_constant_value` Directive.

```ruby
# shareable_constant_value: literal

TABLE = {a: 'ko1', b: 'ko2', c: 'ko3'}
#=> Same as: TABLE = Ractor.make_shareable( {a: 'ko1', b: 'ko2', c: 'ko3'} )
```

`shareable_constant_value` directive accepts the following modes (descriptions use the example: `CONST = expr`):

* none: Do nothing. Same as: `CONST = expr`
* literal:
  * if `expr` consists of literals, replaced to `CONST = Ractor.make_shareable(expr)`.
  * otherwise: replaced to `CONST = expr.tap{|o| raise unless Ractor.shareable?(o)}`.
* experimental_everything: replaced to `CONST = Ractor.make_shareable(expr)`.
* experimental_copy: replaced to `CONST = Ractor.make_shareable(expr, copy: true)`.

Except the `none` mode (default), it is guaranteed that the assigned constants refer to only shareable objects.

See [doc/syntax/comments.rdoc](syntax/comments.rdoc) for more details.

## Implementation note

* Each Ractor has its own thread, it means each Ractor has at least 1 native thread.
* Each Ractor has its own ID (`rb_ractor_t::pub::id`).
  * On debug mode, all unshareable objects are labeled with current Ractor's id, and it is checked to detect unshareable object leak (access an object from different Ractor) in VM.

## Examples

### Traditional Ring example in Actor-model

```ruby
RN = 1_000
CR = Ractor.current

r = Ractor.new do
  p Ractor.receive
  CR << :fin
end

RN.times{
  r = Ractor.new r do |next_r|
    next_r << Ractor.receive
  end
}

p :setup_ok
r << 1
p Ractor.receive
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
    Ractor.yield Ractor.receive
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
# pipeline with send/receive

r3 = Ractor.new Ractor.current do |cr|
  cr.send Ractor.receive + 'r3'
end

r2 = Ractor.new r3 do |r3|
  r3.send Ractor.receive + 'r2'
end

r1 = Ractor.new r2 do |r2|
  r2.send Ractor.receive + 'r1'
end

r1 << 'r0'
p Ractor.receive #=> "r0r1r2r3"
```

### Supervise

```ruby
# ring example again

r = Ractor.current
(1..10).map{|i|
  r = Ractor.new r, i do |r, i|
    r.send Ractor.receive + "r#{i}"
  end
}

r.send "r0"
p Ractor.receive #=> "r0r10r9r8r7r6r5r4r3r2r1"
```

```ruby
# ring example with an error

r = Ractor.current
rs = (1..10).map{|i|
  r = Ractor.new r, i do |r, i|
    loop do
      msg = Ractor.receive
      raise if /e/ =~ msg
      r.send msg + "r#{i}"
    end
  end
}

r.send "r0"
p Ractor.receive #=> "r0r10r9r8r7r6r5r4r3r2r1"
r.send "r0"
p Ractor.select(*rs, Ractor.current) #=> [:receive, "r0r10r9r8r7r6r5r4r3r2r1"]
r.send "e0"
p Ractor.select(*rs, Ractor.current)
#=>
# <Thread:0x000056262de28bd8 run> terminated with exception (report_on_exception is true):
# Traceback (most recent call last):
#         2: from /home/ko1/src/ruby/trunk/test.rb:7:in `block (2 levels) in <main>'
#         1: from /home/ko1/src/ruby/trunk/test.rb:7:in `loop'
# /home/ko1/src/ruby/trunk/test.rb:9:in `block (3 levels) in <main>': unhandled exception
# Traceback (most recent call last):
#         2: from /home/ko1/src/ruby/trunk/test.rb:7:in `block (2 levels) in <main>'
#         1: from /home/ko1/src/ruby/trunk/test.rb:7:in `loop'
# /home/ko1/src/ruby/trunk/test.rb:9:in `block (3 levels) in <main>': unhandled exception
#         1: from /home/ko1/src/ruby/trunk/test.rb:21:in `<main>'
# <internal:ractor>:69:in `select': thrown by remote Ractor. (Ractor::RemoteError)
```

```ruby
# resend non-error message

r = Ractor.current
rs = (1..10).map{|i|
  r = Ractor.new r, i do |r, i|
    loop do
      msg = Ractor.receive
      raise if /e/ =~ msg
      r.send msg + "r#{i}"
    end
  end
}

r.send "r0"
p Ractor.receive #=> "r0r10r9r8r7r6r5r4r3r2r1"
r.send "r0"
p Ractor.select(*rs, Ractor.current)
[:receive, "r0r10r9r8r7r6r5r4r3r2r1"]
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
      msg = Ractor.receive
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

#=> [:receive, "x0r9r9r8r7r6r5r4r3r2r1"]
```
