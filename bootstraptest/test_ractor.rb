# Ractor.current returns a current ractor
assert_equal 'Ractor', %q{
  Ractor.current.class
}

# Ractor.new returns new Ractor
assert_equal 'Ractor', %q{
  Ractor.new{}.class
}

# A Ractor can have a name
assert_equal 'test-name', %q{
  r = Ractor.new name: 'test-name' do
  end
  r.name
}

# If Ractor doesn't have a name, Ractor#name returns nil.
assert_equal 'nil', %q{
  r = Ractor.new do
  end
  r.name.inspect
}

# Raises exceptions if initialize with an invalid name
assert_equal 'ok', %q{
  begin
    r = Ractor.new(name: [{}]) {}
  rescue TypeError => e
    'ok'
  end
}

# Ractor.new must call with a block
assert_equal "must be called with a block", %q{
  begin
    Ractor.new
  rescue ArgumentError => e
    e.message
  end
}

# Ractor#inspect
# Return only id and status for main ractor
assert_equal "#<Ractor:#1 running>", %q{
  Ractor.current.inspect
}

# Return id, loc, and status for no-name ractor
assert_match /^#<Ractor:#([^ ]*?) .+:[0-9]+ terminated>$/, %q{
  r = Ractor.new { '' }
  r.take
  sleep 0.1 until r.inspect =~ /terminated/
  r.inspect
}

# Return id, name, loc, and status for named ractor
assert_match /^#<Ractor:#([^ ]*?) Test Ractor .+:[0-9]+ terminated>$/, %q{
  r = Ractor.new(name: 'Test Ractor') { '' }
  r.take
  sleep 0.1 until r.inspect =~ /terminated/
  r.inspect
}

# A return value of a Ractor block will be a message from the Ractor.
assert_equal 'ok', %q{
  # join
  r = Ractor.new do
    'ok'
  end
  r.take
}

# Passed arguments to Ractor.new will be a block parameter
# The values are passed with Ractor-communication pass.
assert_equal 'ok', %q{
  # ping-pong with arg
  r = Ractor.new 'ok' do |msg|
    msg
  end
  r.take
}

# Pass multiple arguments to Ractor.new
assert_equal 'ok', %q{
  # ping-pong with two args
  r =  Ractor.new 'ping', 'pong' do |msg, msg2|
    [msg, msg2]
  end
  'ok' if r.take == ['ping', 'pong']
}

# Ractor#send passes an object with copy to a Ractor
# and Ractor.receive in the Ractor block can receive the passed value.
assert_equal 'ok', %q{
  r = Ractor.new do
    msg = Ractor.receive
  end
  r.send 'ok'
  r.take
}

# Ractor#receive_if can filter the message
assert_equal '[2, 3, 1]', %q{
  r = Ractor.new Ractor.current do |main|
    main << 1
    main << 2
    main << 3
  end
  a = []
  a << Ractor.receive_if{|msg| msg == 2}
  a << Ractor.receive_if{|msg| msg == 3}
  a << Ractor.receive
}

# Ractor#receive_if with break
assert_equal '[2, [1, :break], 3]', %q{
  r = Ractor.new Ractor.current do |main|
    main << 1
    main << 2
    main << 3
  end

  a = []
  a << Ractor.receive_if{|msg| msg == 2}
  a << Ractor.receive_if{|msg| break [msg, :break]}
  a << Ractor.receive
}

# Ractor#receive_if can't be called recursively
assert_equal '[[:e1, 1], [:e2, 2]]', %q{
  r = Ractor.new Ractor.current do |main|
    main << 1
    main << 2
    main << 3
  end

  a = []

  Ractor.receive_if do |msg|
    begin
      Ractor.receive
    rescue Ractor::Error
      a << [:e1, msg]
    end
    true # delete 1 from queue
  end

  Ractor.receive_if do |msg|
    begin
      Ractor.receive_if{}
    rescue Ractor::Error
      a << [:e2, msg]
    end
    true # delete 2 from queue
  end

  a #
}

###
###
# Ractor still has several memory corruption so skip huge number of tests
if ENV['GITHUB_WORKFLOW'] &&
   ENV['GITHUB_WORKFLOW'] == 'Compilations'
   # ignore the follow
else

# Ractor.select(*ractors) receives a values from a ractors.
# It is similar to select(2) and Go's select syntax.
# The return value is [ch, received_value]
assert_equal 'ok', %q{
  # select 1
  r1 = Ractor.new{'r1'}
  r, obj = Ractor.select(r1)
  'ok' if r == r1 and obj == 'r1'
}

# Ractor.select from two ractors.
assert_equal '["r1", "r2"]', %q{
  # select 2
  r1 = Ractor.new{'r1'}
  r2 = Ractor.new{'r2'}
  rs = [r1, r2]
  as = []
  r, obj = Ractor.select(*rs)
  rs.delete(r)
  as << obj
  r, obj = Ractor.select(*rs)
  as << obj
  as.sort #=> ["r1", "r2"]
}

# Ractor.select from multiple ractors.
assert_equal 30.times.map { 'ok' }.to_s, %q{
  def test n
    rs = (1..n).map do |i|
      Ractor.new(i) do |i|
        "r#{i}"
      end
    end
    as = []
    all_rs = rs.dup

    n.times{
      r, obj = Ractor.select(*rs)
      as << [r, obj]
      rs.delete(r)
    }

    if as.map{|r, o| r.object_id}.sort == all_rs.map{|r| r.object_id}.sort &&
       as.map{|r, o| o}.sort == (1..n).map{|i| "r#{i}"}.sort
      'ok'
    else
      'ng'
    end
  end

  30.times.map{|i|
    test i
  }
} unless ENV['RUN_OPTS'] =~ /--jit-min-calls=5/ # This always fails with --jit-wait --jit-min-calls=5

# Exception for empty select
assert_match /specify at least one ractor/, %q{
  begin
    Ractor.select
  rescue ArgumentError => e
    e.message
  end
}

# Outgoing port of a ractor will be closed when the Ractor is terminated.
assert_equal 'ok', %q{
  r = Ractor.new do
    'finish'
  end

  r.take
  sleep 0.1 until r.inspect =~ /terminated/

  begin
    o = r.take
  rescue Ractor::ClosedError
    'ok'
  else
    "ng: #{o}"
  end
}

# Raise Ractor::ClosedError when try to send into a terminated ractor
assert_equal 'ok', %q{
  r = Ractor.new do
  end

  r.take # closed
  sleep 0.1 until r.inspect =~ /terminated/

  begin
    r.send(1)
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# Raise Ractor::ClosedError when try to send into a closed actor
assert_equal 'ok', %q{
  r = Ractor.new { Ractor.receive }
  r.close_incoming

  begin
    r.send(1)
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# Raise Ractor::ClosedError when try to take from closed actor
assert_equal 'ok', %q{
  r = Ractor.new do
    Ractor.yield 1
    Ractor.receive
  end

  r.close_outgoing
  begin
    r.take
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# Can mix with Thread#interrupt and Ractor#take [Bug #17366]
assert_equal 'err', %q{
  Ractor.new{
    t = Thread.current
    begin
      Thread.new{ t.raise "err" }.join
    rescue => e
      e.message
    end
  }.take
}

# Killed Ractor's thread yields nil
assert_equal 'nil', %q{
  Ractor.new{
    t = Thread.current
    Thread.new{ t.kill }.join
  }.take.inspect #=> nil
}

# Ractor.yield raises Ractor::ClosedError when outgoing port is closed.
assert_equal 'ok', %q{
  r = Ractor.new Ractor.current do |main|
    Ractor.receive
    main << true
    Ractor.yield 1
  end

  r.close_outgoing
  r << true
  Ractor.receive

  begin
    r.take
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# Raise Ractor::ClosedError when try to send into a ractor with closed incoming port
assert_equal 'ok', %q{
  r = Ractor.new { Ractor.receive }
  r.close_incoming

  begin
    r.send(1)
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# A ractor with closed incoming port still can send messages out
assert_equal '[1, 2]', %q{
  r = Ractor.new do
    Ractor.yield 1
    2
  end
  r.close_incoming

  [r.take, r.take]
}

# Raise Ractor::ClosedError when try to take from a ractor with closed outgoing port
assert_equal 'ok', %q{
  r = Ractor.new do
    Ractor.yield 1
    Ractor.receive
  end

  sleep 0.01 # wait for Ractor.yield in r
  r.close_outgoing
  begin
    r.take
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# A ractor with closed outgoing port still can receive messages from incoming port
assert_equal 'ok', %q{
  r = Ractor.new do
    Ractor.receive
  end

  r.close_outgoing
  begin
    r.send(1)
  rescue Ractor::ClosedError
    'ng'
  else
    'ok'
  end
}

# a ractor with closed outgoing port should terminate
assert_equal 'ok', %q{
  Ractor.new do
    close_outgoing
  end

  true until Ractor.count == 1
  :ok
}

# multiple Ractors can receive (wait) from one Ractor
assert_equal '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]', %q{
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
  }.sort
}

# Ractor.select also support multiple take, receive and yield
assert_equal '[true, true, true]', %q{
  RN = 10
  CR = Ractor.current

  rs = (1..RN).map{
    Ractor.new do
      CR.send 'send' + CR.take #=> 'sendyield'
      'take'
    end
  }
  received = []
  take = []
  yielded = []
  until rs.empty?
    r, v = Ractor.select(CR, *rs, yield_value: 'yield')
    case r
    when :receive
      received << v
    when :yield
      yielded << v
    else
      take << v
      rs.delete r
    end
  end
  [received.all?('sendyield'), yielded.all?(nil), take.all?('take')]
}

# multiple Ractors can send to one Ractor
assert_equal '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]', %q{
  pipe = Ractor.new do
    loop do
      Ractor.yield Ractor.receive
    end
  end

  RN = 10
  RN.times.map{|i|
    Ractor.new pipe, i do |pipe, i|
      pipe << i
    end
  }
  RN.times.map{
    pipe.take
  }.sort
}

# an exception in a Ractor will be re-raised at Ractor#receive
assert_equal '[RuntimeError, "ok", true]', %q{
  r = Ractor.new do
    raise 'ok' # exception will be transferred receiver
  end
  begin
    r.take
  rescue Ractor::RemoteError => e
    [e.cause.class,   #=> RuntimeError
     e.cause.message, #=> 'ok'
     e.ractor == r]   #=> true
  end
}

# threads in a ractor will killed
assert_equal '{:ok=>3}', %q{
  Ractor.new Ractor.current do |main|
    q = Queue.new
    Thread.new do
      q << true
      loop{}
    ensure
      main << :ok
    end

    Thread.new do
      q << true
      while true
      end
    ensure
      main << :ok
    end

    Thread.new do
      q << true
      sleep 1
    ensure
      main << :ok
    end

    # wait for the start of all threads
    3.times{q.pop}
  end

  3.times.map{Ractor.receive}.tally
}

# unshareable object are copied
assert_equal 'false', %q{
  obj = 'str'.dup
  r = Ractor.new obj do |msg|
    msg.object_id
  end

  obj.object_id == r.take
}

# To copy the object, now Marshal#dump is used
assert_equal "allocator undefined for Thread", %q{
  obj = Thread.new{}
  begin
    r = Ractor.new obj do |msg|
      msg
    end
  rescue TypeError => e
    e.message #=> no _dump_data is defined for class Thread
  else
    'ng'
  end
}

# send shareable and unshareable objects
assert_equal "ok", %q{
  echo_ractor = Ractor.new do
    loop do
      v = Ractor.receive
      Ractor.yield v
    end
  end

  class C; end
  module M; end
  S = Struct.new(:a, :b, :c, :d)

  shareable_objects = [
    true,
    false,
    nil,
    1,
    1.1,    # Float
    1+2r,   # Rational
    3+4i,   # Complex
    2**128, # Bignum
    :sym,   # Symbol
    'xyzzy'.to_sym, # dynamic symbol
    'frozen'.freeze, # frozen String
    /regexp/, # regexp literal
    /reg{true}exp/.freeze, # frozen dregexp
    [1, 2].freeze,   # frozen Array which only refers to shareable
    {a: 1}.freeze,   # frozen Hash which only refers to shareable
    [{a: 1}.freeze, 'str'.freeze].freeze, # nested frozen container
    S.new(1, 2).freeze, # frozen Struct
    S.new(1, 2, 3, 4).freeze, # frozen Struct
    (1..2), # Range on Struct
    (1..),  # Range on Struct
    (..1),  # Range on Struct
    C, # class
    M, # module
    Ractor.current, # Ractor
  ]

  unshareable_objects = [
    'mutable str'.dup,
    [:array],
    {hash: true},
    S.new(1, 2),
    S.new(1, 2, 3, 4),
    S.new("a", 2).freeze, # frozen, but refers to an unshareable object
  ]

  results = []

  shareable_objects.map{|o|
    echo_ractor << o
    o2 = echo_ractor.take
    results << "#{o} is copied" unless o.object_id == o2.object_id
  }

  unshareable_objects.map{|o|
    echo_ractor << o
    o2 = echo_ractor.take
    results << "#{o.inspect} is not copied" if o.object_id == o2.object_id
  }

  if results.empty?
    :ok
  else
    results.inspect
  end
}

# frozen Objects are shareable
assert_equal [false, true, false].inspect, %q{
  class C
    def initialize freeze
      @a = 1
      @b = :sym
      @c = 'frozen_str'
      @c.freeze if freeze
      @d = true
    end
  end

  def check obj1
    obj2 = Ractor.new obj1 do |obj|
      obj
    end.take

    obj1.object_id == obj2.object_id
  end

  results = []
  results << check(C.new(true))         # false
  results << check(C.new(true).freeze)  # true
  results << check(C.new(false).freeze) # false
}

# move example2: String
# touching moved object causes an error
assert_equal 'hello world', %q{
  # move
  r = Ractor.new do
    obj = Ractor.receive
    obj << ' world'
  end

  str = 'hello'
  r.send str, move: true
  modified = r.take

  begin
    str << ' exception' # raise Ractor::MovedError
  rescue Ractor::MovedError
    modified #=> 'hello world'
  else
    raise 'unreachable'
  end
}

# move example2: Array
assert_equal '[0, 1]', %q{
  r = Ractor.new do
    ary = Ractor.receive
    ary << 1
  end

  a1 = [0]
  r.send a1, move: true
  a2 = r.take
  begin
    a1 << 2 # raise Ractor::MovedError
  rescue Ractor::MovedError
    a2.inspect
  end
}

# move with yield
assert_equal 'hello', %q{
  r = Ractor.new do
    Thread.current.report_on_exception = false
    obj = 'hello'
    Ractor.yield obj, move: true
    obj << 'world'
  end

  str = r.take
  begin
    r.take
  rescue Ractor::RemoteError
    str #=> "hello"
  end
}

# Access to global-variables are prohibited
assert_equal 'can not access global variables $gv from non-main Ractors', %q{
  $gv = 1
  r = Ractor.new do
    $gv
  end

  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# Access to global-variables are prohibited
assert_equal 'can not access global variables $gv from non-main Ractors', %q{
  r = Ractor.new do
    $gv = 1
  end

  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# $stdin,out,err is Ractor local, but shared fds
assert_equal 'ok', %q{
  r = Ractor.new do
    [$stdin, $stdout, $stderr].map{|io|
      [io.object_id, io.fileno]
    }
  end

  [$stdin, $stdout, $stderr].zip(r.take){|io, (oid, fno)|
    raise "should not be different object" if io.object_id == oid
    raise "fd should be same" unless io.fileno == fno
  }
  'ok'
}

# $DEBUG, $VERBOSE are Ractor local
assert_equal 'true', %q{
  $DEBUG = true
  $VERBOSE = true

  def ractor_local_globals
    /a(b)(c)d/ =~ 'abcd' # for $~
    `echo foo` unless  /solaris/ =~ RUBY_PLATFORM

    {
     # ractor-local (derived from created ractor): debug
     '$DEBUG' => $DEBUG,
     '$-d' => $-d,

     # ractor-local (derived from created ractor): verbose
     '$VERBOSE' => $VERBOSE,
     '$-w' => $-w,
     '$-W' => $-W,
     '$-v' => $-v,

     # process-local (readonly): other commandline parameters
     '$-p' => $-p,
     '$-l' => $-l,
     '$-a' => $-a,

     # process-local (readonly): getpid
     '$$'  => $$,

     # thread local: process result
     '$?'  => $?,

     # scope local: match
     '$~'  => $~.inspect,
     '$&'  => $&,
     '$`'  => $`,
     '$\''  => $',
     '$+'  => $+,
     '$1'  => $1,

     # scope local: last line
     '$_' => $_,

     # scope local: last backtrace
     '$@' => $@,
     '$!' => $!,

     # ractor local: stdin, out, err
     '$stdin'  => $stdin.inspect,
     '$stdout' => $stdout.inspect,
     '$stderr' => $stderr.inspect,
    }
  end

  h = Ractor.new do
    ractor_local_globals
  end.take
  ractor_local_globals == h #=> true
}

# selfs are different objects
assert_equal 'false', %q{
  r = Ractor.new do
    self.object_id
  end
  r.take == self.object_id #=> false
}

# self is a Ractor instance
assert_equal 'true', %q{
  r = Ractor.new do
    self.object_id
  end
  r.object_id == r.take #=> true
}

# given block Proc will be isolated, so can not access outer variables.
assert_equal 'ArgumentError', %q{
  begin
    a = true
    r = Ractor.new do
      a
    end
  rescue => e
    e.class
  end
}

# ivar in shareable-objects are not allowed to access from non-main Ractor
assert_equal 'can not access instance variables of classes/modules from non-main Ractors', %q{
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
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# ivar in shareable-objects are not allowed to access from non-main Ractor
assert_equal 'can not access instance variables of shareable objects from non-main Ractors', %q{
  shared = Ractor.new{}
  shared.instance_variable_set(:@iv, 'str')

  r = Ractor.new shared do |shared|
    p shared.instance_variable_get(:@iv)
  end

  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# ivar in shareable-objects are not allowed to access from non-main Ractor, by @iv (get)
assert_equal 'can not access instance variables of shareable objects from non-main Ractors', %q{
  class Ractor
    def setup
      @foo = ''
    end

    def foo
      @foo
    end
  end

  shared = Ractor.new{}
  shared.setup

  r = Ractor.new shared do |shared|
    p shared.foo
  end

  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# ivar in shareable-objects are not allowed to access from non-main Ractor, by @iv (set)
assert_equal 'can not access instance variables of shareable objects from non-main Ractors', %q{
  class Ractor
    def setup
      @foo = ''
    end
  end

  shared = Ractor.new{}

  r = Ractor.new shared do |shared|
    p shared.setup
  end

  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# But a shareable object is frozen, it is allowed to access ivars from non-main Ractor
assert_equal '11', %q{
  [Object.new, [], ].map{|obj|
    obj.instance_variable_set('@a', 1)
    Ractor.make_shareable obj = obj.freeze

    Ractor.new obj do |obj|
      obj.instance_variable_get('@a')
    end.take.to_s
  }.join
}

# cvar in shareable-objects are not allowed to access from non-main Ractor
assert_equal 'can not access class variables from non-main Ractors', %q{
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
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# Getting non-shareable objects via constants by other Ractors is not allowed
assert_equal 'can not access non-shareable objects in constant C::CONST by non-main Ractor.', %q{
  class C
    CONST = 'str'
  end
  r = Ractor.new do
    C::CONST
  end
  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# Setting non-shareable objects into constants by other Ractors is not allowed
assert_equal 'can not set constants with non-shareable objects by non-main Ractors', %q{
  class C
  end
  r = Ractor.new do
    C::CONST = 'str'
  end
  begin
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# define_method is not allowed
assert_equal "defined in a different Ractor", %q{
  str = "foo"
  define_method(:buggy){|i| str << "#{i}"}
  begin
    Ractor.new{buggy(10)}.take
  rescue => e
    e.cause.message
  end
}

# Immutable Array and Hash are shareable, so it can be shared with constants
assert_equal '[1000, 3]', %q{
  A = Array.new(1000).freeze # [nil, ...]
  H = {a: 1, b: 2, c: 3}.freeze

  Ractor.new{ [A.size, H.size] }.take
}

# Ractor.count
assert_equal '[1, 4, 3, 2, 1]', %q{
  counts = []
  counts << Ractor.count
  ractors = (1..3).map { Ractor.new { Ractor.receive } }
  counts << Ractor.count

  ractors[0].send('End 0').take
  sleep 0.1 until ractors[0].inspect =~ /terminated/
  counts << Ractor.count

  ractors[1].send('End 1').take
  sleep 0.1 until ractors[1].inspect =~ /terminated/
  counts << Ractor.count

  ractors[2].send('End 2').take
  sleep 0.1 until ractors[2].inspect =~ /terminated/
  counts << Ractor.count

  counts.inspect
}

# ObjectSpace.each_object can not handle unshareable objects with Ractors
assert_equal '0', %q{
  Ractor.new{
    n = 0
    ObjectSpace.each_object{|o| n += 1 unless Ractor.shareable?(o)}
    n
  }.take
}

# ObjectSpace._id2ref can not handle unshareable objects with Ractors
assert_equal 'ok', %q{
  s = 'hello'

  Ractor.new s.object_id do |id ;s|
    begin
      s = ObjectSpace._id2ref(id)
    rescue => e
      :ok
    end
  end.take
}

# Ractor.make_shareable(obj)
assert_equal 'true', %q{
  class C
    def initialize
      @a = 'foo'
      @b = 'bar'
    end

    def freeze
      @c = [:freeze_called]
      super
    end

    attr_reader :a, :b, :c
  end
  S = Struct.new(:s1, :s2)
  str = "hello"
  str.instance_variable_set("@iv", "hello")
  /a/ =~ 'a'
  m = $~
  class N < Numeric
    def /(other)
      1
    end
  end
  ary = []; ary << ary

  a = [[1, ['2', '3']],
       {Object.new => "hello"},
       C.new,
       S.new("x", "y"),
       ("a".."b"),
       str,
       ary,             # cycle
       /regexp/,
       /#{'r'.upcase}/,
       m,
       Complex(N.new,0),
       Rational(N.new,0),
       true,
       false,
       nil,
       1, 1.2, 1+3r, 1+4i, # Numeric
  ]
  Ractor.make_shareable(a)

  # check all frozen
  a.each{|o|
    raise o.inspect unless o.frozen?

    case o
    when C
      raise o.a.inspect unless o.a.frozen?
      raise o.b.inspect unless o.b.frozen?
      raise o.c.inspect unless o.c.frozen? && o.c == [:freeze_called]
    when Rational
      raise o.numerator.inspect unless o.numerator.frozen?
    when Complex
      raise o.real.inspect unless o.real.frozen?
    when Array
      if o[0] == 1
        raise o[1][1].inspect unless o[1][1].frozen?
      end
    when Hash
      o.each{|k, v|
        raise k.inspect unless k.frozen?
        raise v.inspect unless v.frozen?
      }
    end
  }

  Ractor.shareable?(a)
}

# Ractor.make_shareable(obj) doesn't freeze shareable objects
assert_equal 'true', %q{
  r = Ractor.new{}
  Ractor.make_shareable(a = [r])
  [a.frozen?, a[0].frozen?] == [true, false]
}

# Ractor.make_shareable(a_proc) makes a proc shareable.
assert_equal 'true', %q{
  a = [1, [2, 3], {a: "4"}]
  pr = Proc.new do
    a
  end
  Ractor.make_shareable(a) # referred value should be shareable
  Ractor.make_shareable(pr)
  Ractor.shareable?(pr)
}

# Ractor.shareable?(recursive_objects)
assert_equal '[false, false]', %q{
  y = []
  x = [y, {}].freeze
  y << x
  y.freeze
  [Ractor.shareable?(x), Ractor.shareable?(y)]
}

# Ractor.make_shareable(recursive_objects)
assert_equal '[:ok, false, false]', %q{
  o = Object.new
  def o.freeze; raise; end
  y = []
  x = [y, o].freeze
  y << x
  y.freeze
  [(Ractor.make_shareable(x) rescue :ok), Ractor.shareable?(x), Ractor.shareable?(y)]
}

# define_method() can invoke different Ractor's proc if the proc is shareable.
assert_equal '1', %q{
  class C
    a = 1
    define_method "foo", Ractor.make_shareable(Proc.new{ a })
    a = 2
  end

  Ractor.new{ C.new.foo }.take
}

# Ractor.make_shareable(a_proc) makes a proc shareable.
assert_equal 'can not make a Proc shareable because it accesses outer variables (a).', %q{
  a = b = nil
  pr = Proc.new do
    c = b # assign to a is okay because c is block local variable
          # reading b is okay
    a = b # assign to a is not allowed #=> Ractor::Error
  end

  begin
    Ractor.make_shareable(pr)
  rescue => e
    e.message
  end
}

# Ractor.make_shareable(obj, copy: true) makes copied shareable object.
assert_equal '[false, false, true, true]', %q{
  r = []
  o1 = [1, 2, ["3"]]

  o2 = Ractor.make_shareable(o1, copy: true)
  r << Ractor.shareable?(o1) # false
  r << (o1.object_id == o2.object_id) # false

  o3 = Ractor.make_shareable(o1)
  r << Ractor.shareable?(o1) # true
  r << (o1.object_id == o3.object_id) # false
  r
}


# Ractor deep copies frozen objects (ary)
assert_equal '[true, false]', %q{
  Ractor.new([[]].freeze) { |ary|
    [ary.frozen?, ary.first.frozen? ]
  }.take
}

# Ractor deep copies frozen objects (str)
assert_equal '[true, false]', %q{
  s = String.new.instance_eval { @x = []; freeze}
  Ractor.new(s) { |s|
    [s.frozen?, s.instance_variable_get(:@x).frozen?]
  }.take
}

# Can not trap with not isolated Proc on non-main ractor
assert_equal '[:ok, :ok]', %q{
  a = []
  Ractor.new{
    trap(:INT){p :ok}
  }.take
  a << :ok

  begin
    Ractor.new{
      s = 'str'
      trap(:INT){p s}
    }.take
  rescue => Ractor::RemoteError
    a << :ok
  end
}

###
### Synchronization tests
###

N = 100_000

# fstring pool
assert_equal "#{N}#{N}", %Q{
  N = #{N}
  2.times.map{
    Ractor.new{
      N.times{|i| -(i.to_s)}
    }
  }.map{|r| r.take}.join
}

# enc_table
assert_equal "#{N/10}", %Q{
  Ractor.new do
    loop do
      Encoding.find("test-enc-#{rand(5_000)}").inspect
    rescue ArgumentError => e
    end
  end

  src = Encoding.find("UTF-8")
  #{N/10}.times{|i|
    src.replicate("test-enc-\#{i}")
  }
}

# Generic ivtbl
n = N/2
assert_equal "#{n}#{n}", %Q{
  2.times.map{
    Ractor.new do
      #{n}.times do
        obj = ''
        obj.instance_variable_set("@a", 1)
        obj.instance_variable_set("@b", 1)
        obj.instance_variable_set("@c", 1)
        obj.instance_variable_defined?("@a")
      end
    end
  }.map{|r| r.take}.join
}

end # if !ENV['GITHUB_WORKFLOW']
