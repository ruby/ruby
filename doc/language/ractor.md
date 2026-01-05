# Ractor - Ruby's Actor-like concurrency abstraction

Ractors are designed to provide parallel execution of Ruby code without thread-safety concerns.

## Summary

### Multiple Ractors in a ruby process

You can create multiple Ractors which can run ruby code in parallel with each other.

* `Ractor.new{ expr }` creates a new Ractor and `expr` can run in parallel with other ractors on a multi-core computer.
* Ruby processes start with one ractor (called the *main ractor*).
* If the main ractor terminates, all other ractors receive termination requests, similar to how threads behave.
* Each Ractor contains one or more `Thread`s.
  * Threads within the same ractor share a ractor-wide global lock (GVL in MRI terminology), so they can't run in parallel wich each other (without releasing the GVL explicitly in C extensions). Threads in different ractors can run in parallel.
  * The overhead of creating a ractor is slightly above the overhead of creating a thread.

### Limited sharing between Ractors

Ractors don't share all objects, unlike threads which can access any object other than objects stored in another thread's thread-locals.

* Most objects are *unshareable objects*. Unshareable objects can only be used by the ractor that instantiated them, so you don't need to worry about thread-safety issues resulting from using the object concurrently across ractors.
* Some objects are *shareable objects*. Here is an incomplete list to give you an idea:
  * `i = 123`: All `Integer`s are shareable.
  * `s = "str".freeze`: Frozen strings are shareable if they have no instance variables that refer to unshareable objects.
  * `a = [1, [2], 3].freeze`: `a` is not a shareable object because `a` refers to the unshareable object `[2]` (this Array is not frozen).
  * `h = {c: Object}.freeze`: `h` is shareable because `Symbol`s and `Class`es are shareable, and the Hash is frozen.
  * Class/Module objects are always shareable, even if they refer to unshareable objects.
  * Special shareable objects
    * Ractor objects themselves are shareable.
    * And more...

### Communication between Ractors with `Ractor::Port`

Ractors communicate with each other and synchronize their execution by exchanging messages. The `Ractor::Port` class provides this communication mechanism.

```ruby
port = Ractor::Port.new

Ractor.new port do |port|
  # Other ractors can send to the port
  port << 42
end

port.receive # get a message from the port. Only the ractor that created the Port can receive from it.
#=> 42
```

All Ractors have a default port, which `Ractor#send`, `Ractor.receive` (etc) will use.

### Copy & Move semantics when sending objects

To send unshareable objects to another ractor, objects are either copied or moved.

* Copy: deep-copies the object to the other ractor. All unshareable objects will be `Kernel#clone`ed.
* Move: moves membership to another ractor.
  * The sending ractor can not access the moved object after it moves.
  * There is a guarantee that only one ractor can access an unshareable object at once.

### Thread-safety

Ractors help to write thread-safe, concurrent programs. They allow sharing of data only through explicit message passing for
unshareable objects. Shareable objects are guaranteed to work correctly across ractors, even if the ractors are running in parallel.
This guarantee, however, only applies across ractors. You still need to use `Mutex`es and other thread-safety tools within a ractor if
you're using multiple ruby `Thread`s.

  * Most objects are unshareable. You can't create data-races across ractors due to the inability to use these objects across ractors.
  * Shareable objects are protected by locks (or otherwise don't need to be) so they can be used by more than one ractor at once.

## Creation and termination

### `Ractor.new`

* `Ractor.new { expr }` creates a Ractor.

```ruby
# Ractor.new with a block creates a new Ractor
r = Ractor.new do
  # This block can run in parallel with other ractors
end

# You can name a Ractor with a `name:` argument.
r = Ractor.new name: 'my-first-ractor' do
end

r.name #=> 'my-first-ractor'
```

### Block isolation

The Ractor executes `expr` in the given block.
The given block will be isolated from its outer scope. To prevent sharing objects between ractors, outer variables, `self` and other information is isolated from the block.

This isolation occurs at Ractor creation time (when `Ractor.new` is called). If the given block is not able to be isolated because of outer variables or `self`, an error will be raised.

```ruby
begin
  a = true
  r = Ractor.new do
    a #=> ArgumentError because this block accesses outer variable `a`.
  end
  r.join # wait for ractor to finish
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

Arguments passed to `Ractor.new()` become block parameters for the given block. However, Ruby does not pass the objects themselves, but sends them as messages (see below for details).

```ruby
r = Ractor.new 'ok' do |msg|
  msg #=> 'ok'
end
r.value #=> 'ok'
```

```ruby
# similar to the last example
r = Ractor.new do
  msg = Ractor.receive
  msg
end
r.send 'ok'
r.value #=> 'ok'
```

### The execution result of the given block

The return value of the given block becomes an outgoing message (see below for details).

```ruby
r = Ractor.new do
  'ok'
end
r.value #=> `ok`
```

An error in the given block will be propagated to the consumer of the outgoing message.

```ruby
r = Ractor.new do
  raise 'ok' # exception will be transferred to the consumer
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

Communication between ractors is achieved by sending and receiving messages. There are two ways to communicate:

* (1) Sending and receiving messages via `Ractor::Port`
* (2) Using shareable container objects. For example, the Ractor::TVar gem ([ko1/ractor-tvar](https://github.com/ko1/ractor-tvar))

Users can control program execution timing with (1), but should not control with (2) (only perform critical sections).

For sending and receiving messages, these are the fundamental APIs:

* send/receive via `Ractor::Port`.
    * `Ractor::Port#send(obj)` (`Ractor::Port#<<(obj)` is an alias) sends a message to the port. Ports are connected to an infinite size incoming queue so sending will never block the caller.
    * `Ractor::Port#receive` dequeues a message from its own incoming queue. If the incoming queue is empty, `Ractor::Port#receive` will block the execution of the current Thread until a message is sent.
    * `Ractor#send` and `Ractor.receive` use ports (their default port) internally, so are conceptually similar to the above.
* You can close a `Ractor::Port` by `Ractor::Port#close`. A port can only be closed by the ractor that created it.
    * If a port is closed, you can't `send` to it. Doing so raises an exception.
    * When a ractor is terminated, the ractor's ports are automatically closed.
* You can wait for a ractor's termination and receive its return value with `Ractor#value`. This is similar to `Thread#value`.

There are 3 ways to send an object as a message:

1) Send a reference: sending a shareable object sends only a reference to the object (fast).

2) Copy an object: sending an unshareable object through copying it deeply (can be slow). Note that you can not send an object this way which does not support deep copy. Some `T_DATA` objects (objects whose class is defined in a C extension, such as `StringIO`) are not supported.

3) Move an object: sending an unshareable object across ractors with a membership change. The sending Ractor can not access the moved object after moving it, otherwise an exception will be raised. Implementation note: `T_DATA` objects are not supported.

You can choose between "Copy" and "Move" by the `move:` keyword, `Ractor#send(obj, move: true/false)`. The default is `false` ("Copy"). However, if the object is shareable it will automatically use `move`.

### Wait for multiple Ractors with `Ractor.select`

You can wait for messages on multiple ports at once.
The return value of `Ractor.select()` is `[port, msg]` where `port` is a ready port and `msg` is the received message.

To make it convenient, `Ractor.select` can also accept ractors. In this case, it waits for their termination.
The return value of `Ractor.select()` is `[r, msg]` where `r` is a terminated Ractor and `msg` is the value of the ractor's block.

Wait for a single ractor (same as `Ractor#value`):

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
values = []

while rs.any?
  r, obj = Ractor.select(*rs)
  rs.delete(r)
  values << obj
end

values.sort == ['r1', 'r2'] #=> true
```

NOTE: Using `Ractor.select()` on a very large number of ractors has the same issue as `select(2)` currently.

### Closing ports

* `Ractor::Port#close` closes the port (similar to `Queue#close`).
  * `port.send(obj)` will raise an exception when the port is closed.
  * When the queue connected to the port is empty and port is closed, `Ractor::Port#receive` raises an exception. If the queue is not empty, it dequeues an object without exceptions.
* When a Ractor terminates, the ports are closed automatically.

Example (try to get a result from closed ractor):

```ruby
r = Ractor.new do
  'finish'
end
r.join # success (wait for the termination)
r.value # success (will return 'finish')

# The ractor's termination value has already been given to another ractor
Ractor.new r do |r|
  r.value #=> Ractor::Error
end.join
```

Example (try to send to closed port):

```ruby
r = Ractor.new do
end

r.join # wait for termination, closes default port

begin
  r.send(1)
rescue Ractor::ClosedError
  'ok'
end
```

### Send a message by copying

`Ractor::Port#send(obj)` copies `obj` deeply if `obj` is an unshareable object.

```ruby
obj = 'str'.dup
r = Ractor.new obj do |msg|
  # return received msg's object_id
  msg.object_id
end

obj.object_id == r.value #=> false
```

Some objects do not support copying, and raise an exception.

```ruby
obj = Thread.new{}
begin
  Ractor.new obj do |msg|
    msg
  end
rescue TypeError => e
  e.message #=> #<TypeError: allocator undefined for Thread>
end
```

### Send a message by moving

`Ractor::Port#send(obj, move: true)` moves `obj` to the destination Ractor.
If the source ractor uses the moved object (for example, calls a method like `obj.foo()`), it will raise an error.

```ruby
r = Ractor.new do
  obj = Ractor.receive
  obj << ' world'
end

str = 'hello'.dup
r.send str, move: true
# str is now moved, and accessing str from this ractor is prohibited
modified = r.value #=> 'hello world'


begin
  # Error because it uses moved str.
  str << ' exception' # raise Ractor::MovedError
rescue Ractor::MovedError
  modified #=> 'hello world'
end
```

Some objects do not support moving, and an exception will be raised.

```ruby
r = Ractor.new do
  Ractor.receive
end

r.send(Thread.new{}, move: true) #=> allocator undefined for Thread (TypeError)
```

Once an object has been moved, the source object's class is changed to `Ractor::MovedObject`.

### Shareable objects

The following is an inexhaustive list of shareable objects:

* `Integer`, `Float`, `Complex`, `Rational`
* `Symbol`, frozen `String` objects that don't refer to unshareables, `true`, `false`, `nil`
* `Regexp` objects, if they have no instance variables or their instance variables refer only to shareables
* `Class` and `Module` objects
* `Ractor` and other special objects which deal with synchronization

To make objects shareable, `Ractor.make_shareable(obj)` is provided. It tries to make the object shareable by freezing `obj` and recursively traversing its references to freeze them all. This method accepts the `copy:` keyword (default value is false). `Ractor.make_shareable(obj, copy: true)` tries to make a deep copy of `obj` and make the copied object shareable. `Ractor.make_shareable(copy: false)` has no effect on an already shareable object. If the object cannot be made shareable, a `Ractor::Error` exception will be raised.

## Language changes to limit sharing between Ractors

To isolate unshareable objects across ractors, we introduced additional language semantics for multi-ractor Ruby programs.

Note that when not using ractors, these additional semantics are not needed (100% compatible with Ruby 2).

### Global variables

Only the main Ractor can access global variables.

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

Note that some special global variables, such as `$stdin`, `$stdout` and `$stderr` are local to each ractor. See [[Bug #17268]](https://bugs.ruby-lang.org/issues/17268) for more details.

### Instance variables of shareable objects

Instance variables of classes/modules can be accessed from non-main ractors only if their values are shareable objects.

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

Only the main Ractor can read constants which refer to an unshareable object.

```ruby
class C
  CONST = 'str'.dup
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

Only the main Ractor can define constants which refer to an unshareable object.

```ruby
class C
end
r = Ractor.new do
  C::CONST = 'str'.dup
end
begin
  r.join
rescue => e
  e.class #=> Ractor::IsolationError
end
```

When creating/updating a library to support ractors, constants should only refer to shareable objects if they are to be used by non-main ractors.

```ruby
TABLE = {a: 'ko1', b: 'ko2', c: 'ko3'}
```

In this case, `TABLE` refers to an unshareable Hash object. In order for other ractors to use `TABLE`, we need to make it shareable. We can use `Ractor.make_shareable()` like so:

```ruby
TABLE = Ractor.make_shareable( {a: 'ko1', b: 'ko2', c: 'ko3'} )
```

To make it easy, Ruby 3.0 introduced a new `shareable_constant_value` file directive.

```ruby
# shareable_constant_value: literal

TABLE = {a: 'ko1', b: 'ko2', c: 'ko3'}
#=> Same as: TABLE = Ractor.make_shareable( {a: 'ko1', b: 'ko2', c: 'ko3'} )
```

The `shareable_constant_value` directive accepts the following modes (descriptions use the example: `CONST = expr`):

* none: Do nothing. Same as: `CONST = expr`
* literal:
  * if `expr` consists of literals, replaced to `CONST = Ractor.make_shareable(expr)`.
  * otherwise: replaced to `CONST = expr.tap{|o| raise unless Ractor.shareable?(o)}`.
* experimental_everything: replaced to `CONST = Ractor.make_shareable(expr)`.
* experimental_copy: replaced to `CONST = Ractor.make_shareable(expr, copy: true)`.

Except for the `none` mode (default), it is guaranteed that these constants refer only to shareable objects.

See [syntax/comments.rdoc](../syntax/comments.rdoc) for more details.

### Shareable procs

Procs and lambdas are unshareable objects, even when they are frozen. To create an unshareable Proc, you must use `Ractor.shareable_proc { expr }`. Much like during Ractor creation, the proc's block is isolated from its outer environment, so it cannot access variables from the outside scope. `self` is also changed within the Proc to be `nil` by default, although a `self:` keyword can be provided if you want to customize the value to a different shareable object.

```ruby
p = Ractor.shareable_proc { p self }
p.call #=> nil
```

```ruby
begin
  a = 1
  pr = Ractor.shareable_proc { p a }
  pr.call # never gets here
rescue Ractor::IsolationError
end
```

In order to dynamically define a method with `Module#define_method` that can be used from different ractors, you must define it with a shareable proc. Alternatively, you can use `Module#class_eval` or `Module#module_eval` with a String. Even though the shareable proc's `self` is initially bound to `nil`, `define_method` will bind `self` to the correct value in the method.

```ruby
class A
  define_method :testing, &Ractor.shareable_proc do
    p self
  end
end
Ractor.new do
  a = A.new
  a.testing #=> #<A:0x0000000101acfe10>
end.join
```

This isolation must be done to prevent the method from accessing and assigning captured outer variables across ractors.

### Ractor-local storage

You can store any object (even unshareables) in ractor-local storage.

```ruby
r = Ractor.new do
  values = []
  Ractor[:threads] = []
  3.times do |i|
    Ractor[:threads] << Thread.new do
      values << [Ractor.receive, i+1] # Ractor.receive blocks the current thread in the current ractor until it receives a message
    end
  end
  Ractor[:threads].each(&:join)
  values
end

r << 1
r << 2
r << 3
r.value #=> [[1,1],[2,2],[3,3]] (the order can change with each run)
```

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
