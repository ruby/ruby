# Ractor - Ruby's Actor-like concurrent abstraction

Ractor is designed to provide a parallel execution feature of Ruby without thread-safety concerns.

## Summary

### Multiple Ractors in an interpreter process

You can make multiple Ractors and they run in parallel.

* `Ractor.new{ expr }` creates a new Ractor and `expr` is run in parallel on a parallel computer.
* Interpreter invokes with the first Ractor (called *main Ractor*).
* If the main Ractor terminates, all other Ractors receive termination requests, similar to how threads behave. (if main thread (first invoked Thread), Ruby interpreter sends all running threads to terminate execution).
* Each Ractor contains one or more Threads.
  * Threads within the same Ractor share a Ractor-wide global lock like GIL (GVL in MRI terminology), so they can't run in parallel (without releasing GVL explicitly in C-level). Threads in different ractors run in parallel.
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

### Communication between Ractors with `Ractor::Port`

Ractors communicate with each other and synchronize the execution by message exchanging between Ractors. `Ractor::Port` is provided for this communication.

```ruby
port = Ractor::Port.new

Ractor.new port do |port|
  # Other ractors can send to the port
  port << 42
end

port.receive # get a message to the port. Only the creator Ractor can receive from the port
#=> 42
```

Ractors have its own default port and `Ractor#send`, `Ractor.receive` will use it.

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
  * There are several blocking operations (waiting send) so you can make a program which has dead-lock and live-lock issues.
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
  r.join # see later
rescue ArgumentError
end
```

* The `self` of the given block is the `Ractor` object itself.

```ruby
r = Ractor.new do
  p self.class #=> Ractor
  self.object_id
end
r.value == self.object_id #=> false
```

Passed arguments to `Ractor.new()` becomes block parameters for the given block. However, an interpreter does not pass the parameter object references, but send them as messages (see below for details).

```ruby
r = Ractor.new 'ok' do |msg|
  msg #=> 'ok'
end
r.value #=> 'ok'
```

```ruby
# almost similar to the last example
r = Ractor.new do
  msg = Ractor.receive
  msg
end
r.send 'ok'
r.value #=> 'ok'
```

### An execution result of given block

Return value of the given block becomes an outgoing message (see below for details).

```ruby
r = Ractor.new do
  'ok'
end
r.value #=> `ok`
```

Error in the given block will be propagated to the receiver of an outgoing message.

```ruby
r = Ractor.new do
  raise 'ok' # exception will be transferred to the receiver
end

begin
  r.value
rescue Ractor::RemoteError => e
  e.cause.class   #=> RuntimeError
  e.cause.message #=> 'ok'
  e.ractor        #=> r
end
```

## Communication between Ractors

Communication between Ractors is achieved by sending and receiving messages. There are two ways to communicate with each other.

* (1) Message sending/receiving via `Ractor::Port`
* (2) Using shareable container objects
  * Ractor::TVar gem ([ko1/ractor-tvar](https://github.com/ko1/ractor-tvar))
  * more?

Users can control program execution timing with (1), but should not control with (2) (only manage as critical section).

For message sending and receiving, there are two types of APIs: push type and pull type.

* (1) send/receive via `Ractor::Port`.
  * `Ractor::Port#send(obj)` (`Ractor::Port#<<(obj)` is an alias) send a message to the port. Ports are connected to the infinite size incoming queue so `Ractor::Port#send` will never block.
  * `Ractor::Port#receive` dequeue a message from its own incoming queue. If the incoming queue is empty, `Ractor::Port#receive` calling will block the execution of a thread.
* `Ractor.select()` can wait for the success of `Ractor::Port#receive`.
* You can close `Ractor::Port` by `Ractor::Port#close` only by the creator Ractor of the port.
  * If the port is closed, you can't `send` to the port. If `Ractor::Port#receive` is blocked for the closed port, then it will raise an exception.
  * When a Ractor is terminated, the Ractor's ports are closed.
* There are 3 ways to send an object as a message
  * (1) Send a reference: Sending a shareable object, send only a reference to the object (fast)
  * (2) Copy an object: Sending an unshareable object by copying an object deeply (slow). Note that you can not send an object which does not support deep copy. Some `T_DATA` objects (objects whose class is defined in a C extension, such as `StringIO`) are not supported.
  * (3) Move an object: Sending an unshareable object reference with a membership. Sender Ractor can not access moved objects anymore (raise an exception) after moving it. Current implementation makes new object as a moved object for receiver Ractor and copies references of sending object to moved object. `T_DATA` objects are not supported.
  * You can choose "Copy" and "Move" by the `move:` keyword, `Ractor#send(obj, move: true/false)` and `Ractor.yield(obj, move: true/false)` (default is `false` (COPY)).

### Wait for multiple Ractors with `Ractor.select`

You can wait multiple Ractor port's receiving.
The return value of `Ractor.select()` is `[port, msg]` where `port` is a ready port and `msg` is received message.

To make convenient, `Ractor.select` can also accept Ractors to wait the termination of Ractors.
The return value of `Ractor.select()` is `[r, msg]` where `r` is a terminated Ractor and `msg` is the value of Ractor's block.

Wait for a single ractor (same as `Ractor#value`):

```ruby
r1 = Ractor.new{'r1'}

r, obj = Ractor.select(r1)
r == r1 and obj == 'r1' #=> true
```

Waiting for two ractors:

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

TODO: Current `Ractor.select()` has the same issue of `select(2)`, so this interface should be refined.

TODO: `select` syntax of go-language uses round-robin technique to make fair scheduling. Now `Ractor.select()` doesn't use it.

### Closing Ractor's ports

* `Ractor::Port#close` close the ports (similar to `Queue#close`).
  * `port.send(obj)` where `port` is closed, will raise an exception.
  * When the queue connected to the port is empty and port is closed, `Ractor::Port#receive` raises an exception. If the queue is not empty, it dequeues an object without exceptions.
* When a Ractor terminates, the ports are closed automatically.

Example (try to get a result from closed Ractor):

```ruby
r = Ractor.new do
  'finish'
end
r.join # success (wait for the termination)
r.value # success (will return 'finish')

# the first Ractor which success the `Ractor#value` can get the result
Ractor.new r do |r|
  r.value #=> Ractor::Error
end
```

Example (try to send to closed (terminated) Ractor):

```ruby
r = Ractor.new do
end

r.join # wait terminate

begin
  r.send(1)
rescue Ractor::ClosedError
  'ok'
else
  'ng'
end
```

### Send a message by copying

`Ractor::Port#send(obj)` copy `obj` deeply if `obj` is an unshareable object.

```ruby
obj = 'str'.dup
r = Ractor.new obj do |msg|
  # return received msg's object_id
  msg.object_id
end

obj.object_id == r.value #=> false
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

`Ractor::Port#send(obj, move: true)` moves `obj` to the destination Ractor.
If the source Ractor touches the moved object (for example, call the method like `obj.foo()`), it will be an error.

```ruby
# move with Ractor#send
r = Ractor.new do
  obj = Ractor.receive
  obj << ' world'
end

str = 'hello'
r.send str, move: true
modified = r.value #=> 'hello world'

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

To make shareable objects, `Ractor.make_shareable(obj)` method is provided. In this case, try to make shareable by freezing `obj` and recursively traversable objects. This method accepts `copy:` keyword (default value is false).`Ractor.make_shareable(obj, copy: true)` tries to make a deep copy of `obj` and make the copied object shareable.

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
  r.join
rescue Ractor::RemoteError => e
  e.cause.message #=> 'can not access global variables from non-main Ractors'
end
```

Note that some special global variables, such as `$stdin`, `$stdout` and `$stderr` are Ractor-local. See [[Bug #17268]](https://bugs.ruby-lang.org/issues/17268) for more details.

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
end.value #=> 1
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
end.join
```



```ruby
shared = Ractor.new{}
shared.instance_variable_set(:@iv, 'str')

r = Ractor.new shared do |shared|
  p shared.instance_variable_get(:@iv)
end

begin
  r.join
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
  r.join
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
  r.join
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
  r.join
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

(1) One ractor has a pool

```ruby
require 'prime'

N = 1000
RN = 10

# make RN workers
workers = (1..RN).map do
  Ractor.new do |; result_port|
    loop do
      n, result_port = Ractor.receive
      result_port << [n, n.prime?, Ractor.current]
    end
  end
end

result_port = Ractor::Port.new
results = []

(1..N).each do |i|
  if workers.empty?
    # receive a result
    n, result, w = result_port.receive
    results << [n, result]
  else
    w = workers.pop
  end

  # send a task to the idle worker ractor
  w << [i, result_port]
end

# receive a result
while results.size != N
  n, result, _w = result_port.receive
  results << [n, result]
end

pp results.sort_by{|n, result| n}
```

### Pipeline

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
