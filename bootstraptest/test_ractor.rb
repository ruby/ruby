# Ractor.current returns a current ractor
assert_equal 'Ractor', %q{
  Ractor.current.class
}

# Ractor.new returns new Ractor
assert_equal 'Ractor', %q{
  Ractor.new{}.class
}

# Ractor.allocate is not supported
assert_equal "[:ok, :ok]", %q{
  rs = []
  begin
    Ractor.allocate
  rescue => e
    rs << :ok if e.message == 'allocator undefined for Ractor'
  end

  begin
    Ractor.new{}.dup
  rescue
    rs << :ok if e.message == 'allocator undefined for Ractor'
  end

  rs
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
  r.join
  sleep 0.1 until r.inspect =~ /terminated/
  r.inspect
}

# Return id, name, loc, and status for named ractor
assert_match /^#<Ractor:#([^ ]*?) Test Ractor .+:[0-9]+ terminated>$/, %q{
  r = Ractor.new(name: 'Test Ractor') { '' }
  r.join
  sleep 0.1 until r.inspect =~ /terminated/
  r.inspect
}

# A return value of a Ractor block will be a message from the Ractor.
assert_equal 'ok', %q{
  # join
  r = Ractor.new do
    'ok'
  end
  r.value
}

# Passed arguments to Ractor.new will be a block parameter
# The values are passed with Ractor-communication pass.
assert_equal 'ok', %q{
  # ping-pong with arg
  r = Ractor.new 'ok' do |msg|
    msg
  end
  r.value
}

# Pass multiple arguments to Ractor.new
assert_equal 'ok', %q{
  # ping-pong with two args
  r =  Ractor.new 'ping', 'pong' do |msg, msg2|
    [msg, msg2]
  end
  'ok' if r.value == ['ping', 'pong']
}

# Ractor#send passes an object with copy to a Ractor
# and Ractor.receive in the Ractor block can receive the passed value.
assert_equal 'ok', %q{
  r = Ractor.new do
    msg = Ractor.receive
  end
  r.send 'ok'
  r.value
}

# Ractor#receive_if can filter the message
assert_equal '[1, 2, 3]', %q{
  ports = 3.times.map{Ractor::Port.new}

  r = Ractor.new ports do |ports|
    ports[0] << 3
    ports[1] << 1
    ports[2] << 2
  end
  a = []
  a << ports[1].receive # 1
  a << ports[2].receive # 2
  a << ports[0].receive # 3
  a
}

# dtoa race condition
assert_equal '[:ok, :ok, :ok]', %q{
  n = 3
  n.times.map{
    Ractor.new{
      10_000.times{ rand.to_s }
      :ok
    }
  }.map(&:value)
}

# Ractor.make_shareable issue for locals in proc [Bug #18023]
assert_equal '[:a, :b, :c, :d, :e]', %q{
  v1, v2, v3, v4, v5 = :a, :b, :c, :d, :e
  closure = Ractor.current.instance_eval{ Proc.new { [v1, v2, v3, v4, v5] } }

  Ractor.make_shareable(closure).call
}

# Ractor.make_shareable issue for locals in proc [Bug #18023]
assert_equal '[:a, :b, :c, :d, :e, :f, :g]', %q{
  a = :a
  closure = Ractor.current.instance_eval do
    -> {
      b, c, d = :b, :c, :d
      -> {
        e, f, g = :e, :f, :g
        -> { [a, b, c, d, e, f, g] }
      }.call
    }.call
  end

  Ractor.make_shareable(closure).call
}

###
###
# Ractor still has several memory corruption so skip huge number of tests
if ENV['GITHUB_WORKFLOW'] == 'Compilations'
   # ignore the follow
else

# Ractor.select with a Ractor argument
assert_equal 'ok', %q{
  # select 1
  r1 = Ractor.new{'r1'}
  port, obj = Ractor.select(r1)
  if port == r1 and obj == 'r1'
    'ok'
  else
    # failed
    [port, obj].inspect
  end
}

# Ractor.select from two ractors.
assert_equal '["r1", "r2"]', %q{
  # select 2
  p1 = Ractor::Port.new
  p2 = Ractor::Port.new
  r1 = Ractor.new(p1){|p1| p1 << 'r1'}
  r2 = Ractor.new(p2){|p2| p2 << 'r2'}
  ps = [p1, p2]
  as = []
  port, obj = Ractor.select(*ps)
  ps.delete(port)
  as << obj
  port, obj = Ractor.select(*ps)
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
} unless (ENV.key?('TRAVIS') && ENV['TRAVIS_CPU_ARCH'] == 'arm64') # https://bugs.ruby-lang.org/issues/17878

# Exception for empty select
assert_match /specify at least one ractor/, %q{
  begin
    Ractor.select
  rescue ArgumentError => e
    e.message
  end
}

# Raise Ractor::ClosedError when try to send into a terminated ractor
assert_equal 'ok', %q{
  r = Ractor.new do
  end

  r.join # closed
  sleep 0.1 until r.inspect =~ /terminated/

  begin
    r.send(1)
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# Can mix with Thread#interrupt and Ractor#join [Bug #17366]
assert_equal 'err', %q{
  Ractor.new do
    t = Thread.current
    begin
      Thread.new{ t.raise "err" }.join
    rescue => e
      e.message
    end
  end.value
}

# Killed Ractor's thread yields nil
assert_equal 'nil', %q{
  Ractor.new{
    t = Thread.current
    Thread.new{ t.kill }.join
  }.value.inspect #=> nil
}

# Raise Ractor::ClosedError when try to send into a ractor with closed default port
assert_equal 'ok', %q{
  r = Ractor.new {
    Ractor.current.close
    Ractor.main << :ok
    Ractor.receive
  }

  Ractor.receive # wait for ok

  begin
    r.send(1)
  rescue Ractor::ClosedError
    'ok'
  else
    'ng'
  end
}

# Ractor.main returns main ractor
assert_equal 'true', %q{
  Ractor.new{
    Ractor.main
  }.value == Ractor.current
}

# a ractor with closed outgoing port should terminate
assert_equal 'ok', %q{
  Ractor.new do
    Ractor.current.close
  end

  true until Ractor.count == 1
  :ok
}

# an exception in a Ractor main thread will be re-raised at Ractor#receive
assert_equal '[RuntimeError, "ok", true]', %q{
  r = Ractor.new do
    raise 'ok' # exception will be transferred receiver
  end
  begin
    r.join
  rescue Ractor::RemoteError => e
    [e.cause.class,   #=> RuntimeError
     e.cause.message, #=> 'ok'
     e.ractor == r]   #=> true
  end
}

# an exception in a Ractor will be re-raised at Ractor#value
assert_equal '[RuntimeError, "ok", true]', %q{
  r = Ractor.new do
    raise 'ok' # exception will be transferred receiver
  end
  begin
    r.value
  rescue Ractor::RemoteError => e
    [e.cause.class,   #=> RuntimeError
     e.cause.message, #=> 'ok'
     e.ractor == r]   #=> true
  end
}

# an exception in a Ractor non-main thread will not be re-raised at Ractor#receive
assert_equal 'ok', %q{
  r = Ractor.new do
    Thread.new do
      raise 'ng'
    end
    sleep 0.1
    'ok'
  end
  r.value
}

# threads in a ractor will killed
assert_equal '{ok: 3}', %q{
  Ractor.new Ractor.current do |main|
    q = Thread::Queue.new
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
} unless yjit_enabled? # `[BUG] Bus Error at 0x000000010b7002d0` in jit_exec()

# unshareable object are copied
assert_equal 'false', %q{
  obj = 'str'.dup
  r = Ractor.new obj do |msg|
    msg.object_id
  end

  obj.object_id == r.value
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

# many echos
assert_equal "ok", <<~'RUBY', frozen_string_literal: false
  port = Ractor::Port.new
  echo_ractor = Ractor.new port do |port|
    loop do
      v = Ractor.receive
      port << v
    end
  end

  10_000.times do |i|
    echo_ractor << i
    raise unless port.receive == i
  end
  :ok
RUBY

# many echos threaded
assert_equal "ok", <<~'RUBY', frozen_string_literal: false
  4.times.map do
    Thread.new do
      port = Ractor::Port.new
      echo_ractor = Ractor.new port do |port|
        loop do
          v = Ractor.receive
          port << v
        end
      end

      10_000.times do |i|
        echo_ractor << i
        raise unless port.receive == i
      end
    end
  end.each(&:join)
  :ok
RUBY

# send shareable and unshareable objects
assert_equal "ok", <<~'RUBY', frozen_string_literal: false
  port = Ractor::Port.new
  echo_ractor = Ractor.new port do |port|
    loop do
      v = Ractor.receive
      port << v
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
    o2 = port.receive
    results << "#{o} is copied" unless o.object_id == o2.object_id
  }

  unshareable_objects.map{|o|
    echo_ractor << o
    o2 = port.receive
    results << "#{o.inspect} is not copied" if o.object_id == o2.object_id
  }

  if results.empty?
    :ok
  else
    results.inspect
  end
RUBY

# frozen Objects are shareable
assert_equal [false, true, false].inspect, <<~'RUBY', frozen_string_literal: false
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
    end.value

    obj1.object_id == obj2.object_id
  end

  results = []
  results << check(C.new(true))         # false
  results << check(C.new(true).freeze)  # true
  results << check(C.new(false).freeze) # false
RUBY

# move example2: String
# touching moved object causes an error
assert_equal 'hello world', <<~'RUBY', frozen_string_literal: false
  # move
  r = Ractor.new do
    obj = Ractor.receive
    obj << ' world'
  end

  str = 'hello'
  r.send str, move: true
  modified = r.value

  begin
    str << ' exception' # raise Ractor::MovedError
  rescue Ractor::MovedError
    modified #=> 'hello world'
  else
    raise 'unreachable'
  end
RUBY

# move example2: Array
assert_equal '[0, 1]', %q{
  r = Ractor.new do
    ary = Ractor.receive
    ary << 1
  end

  a1 = [0]
  r.send a1, move: true
  a2 = r.value
  begin
    a1 << 2 # raise Ractor::MovedError
  rescue Ractor::MovedError
    a2.inspect
  end
}

# unshareable frozen objects should still be frozen in new ractor after move
assert_equal 'true', %q{
  r = Ractor.new do
    obj = receive
    { frozen: obj.frozen? }
  end
  obj = [Object.new].freeze
  r.send(obj, move: true)
  r.value[:frozen]
}

# Access to global-variables are prohibited
assert_equal 'can not access global variables $gv from non-main Ractors', %q{
  $gv = 1
  r = Ractor.new do
    $gv
  end

  begin
    r.join
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
    r.join
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

  [$stdin, $stdout, $stderr].zip(r.value){|io, (oid, fno)|
    raise "should not be different object" if io.object_id == oid
    raise "fd should be same" unless io.fileno == fno
  }
  'ok'
}

# $stdin,out,err belong to Ractor
assert_equal 'ok', %q{
  r = Ractor.new do
    $stdin.itself
    $stdout.itself
    $stderr.itself
    'ok'
  end

  r.value
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
  end.value
  ractor_local_globals == h #=> true
}

# selfs are different objects
assert_equal 'false', %q{
  r = Ractor.new do
    self.object_id
  end
  ret = r.value
  ret == self.object_id
}

# self is a Ractor instance
assert_equal 'true', %q{
  r = Ractor.new do
    self.object_id
  end
  ret = r.value
  if r.object_id == ret #=> true
    true
  else
    raise [ret, r.object_id].inspect
  end
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
assert_equal "can not get unshareable values from instance variables of classes/modules from non-main Ractors", <<~'RUBY', frozen_string_literal: false
  class C
    @iv = 'str'
  end

  r = Ractor.new do
    class C
      p @iv
    end
  end

  begin
    r.value
  rescue Ractor::RemoteError => e
    e.cause.message
  end
RUBY

# ivar in shareable-objects are not allowed to access from non-main Ractor
assert_equal 'can not access instance variables of shareable objects from non-main Ractors', %q{
  shared = Ractor.new{}
  shared.instance_variable_set(:@iv, 'str')

  r = Ractor.new shared do |shared|
    p shared.instance_variable_get(:@iv)
  end

  begin
    r.value
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
    r.value
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
    r.value
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
    end.value.to_s
  }.join
}

# and instance variables of classes/modules are accessible if they refer shareable objects
assert_equal '333', %q{
  class C
    @int = 1
    @str = '-1000'.dup
    @fstr = '100'.freeze

    def self.int = @int
    def self.str = @str
    def self.fstr = @fstr
  end

  module M
    @int = 2
    @str = '-2000'.dup
    @fstr = '200'.freeze

    def self.int = @int
    def self.str = @str
    def self.fstr = @fstr
  end

  a = Ractor.new{ C.int }.value
  b = Ractor.new do
    C.str.to_i
  rescue Ractor::IsolationError
    10
  end.value
  c = Ractor.new do
    C.fstr.to_i
  end.value

  d = Ractor.new{ M.int }.value
  e = Ractor.new do
    M.str.to_i
  rescue Ractor::IsolationError
    20
  end.value
  f = Ractor.new do
    M.fstr.to_i
  end.value


  # 1 + 10 + 100 + 2 + 20 + 200
  a + b + c + d + e + f
}

assert_equal '["instance-variable", "instance-variable", nil]', %q{
  class C
    @iv1 = ""
    @iv2 = 42
    def self.iv1 = defined?(@iv1) # "instance-variable"
    def self.iv2 = defined?(@iv2) # "instance-variable"
    def self.iv3 = defined?(@iv3) # nil
  end

  Ractor.new{
    [C.iv1, C.iv2, C.iv3]
  }.value
}

# moved objects have their shape properly set to original object's shape
assert_equal '1234', %q{
  class Obj
    attr_accessor :a, :b, :c, :d
    def initialize
      @a = 1
      @b = 2
      @c = 3
    end
  end
  r = Ractor.new do
    obj = receive
    obj.d = 4
    [obj.a, obj.b, obj.c, obj.d]
  end
  obj = Obj.new
  r.send(obj, move: true)
  values = r.value
  values.join
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
    r.join
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# also cached cvar in shareable-objects are not allowed to access from non-main Ractor
assert_equal 'can not access class variables from non-main Ractors', %q{
  class C
    @@cv = 'str'
    def self.cv
      @@cv
    end
  end

  C.cv # cache

  r = Ractor.new do
    C.cv
  end

  begin
    r.join
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

# Getting non-shareable objects via constants by other Ractors is not allowed
assert_equal 'can not access non-shareable objects in constant C::CONST by non-main Ractor.', <<~'RUBY', frozen_string_literal: false
  class C
    CONST = 'str'
  end
  r = Ractor.new do
    C::CONST
  end
  begin
    r.join
  rescue Ractor::RemoteError => e
    e.cause.message
  end
  RUBY

# Constant cache should care about non-sharable constants
assert_equal "can not access non-shareable objects in constant Object::STR by non-main Ractor.", <<~'RUBY', frozen_string_literal: false
  STR = "hello"
  def str; STR; end
  s = str() # fill const cache
  begin
    Ractor.new{ str() }.join
  rescue Ractor::RemoteError => e
    e.cause.message
  end
RUBY

# Setting non-shareable objects into constants by other Ractors is not allowed
assert_equal 'can not set constants with non-shareable objects by non-main Ractors', <<~'RUBY', frozen_string_literal: false
  class C
  end
  r = Ractor.new do
    C::CONST = 'str'
  end
  begin
    r.join
  rescue Ractor::RemoteError => e
    e.cause.message
  end
RUBY

# define_method is not allowed
assert_equal "defined with an un-shareable Proc in a different Ractor", %q{
  str = "foo"
  define_method(:buggy){|i| str << "#{i}"}
  begin
    Ractor.new{buggy(10)}.join
  rescue => e
    e.cause.message
  end
}

# Immutable Array and Hash are shareable, so it can be shared with constants
assert_equal '[1000, 3]', %q{
  A = Array.new(1000).freeze # [nil, ...]
  H = {a: 1, b: 2, c: 3}.freeze

  Ractor.new{ [A.size, H.size] }.value
}

# Ractor.count
assert_equal '[1, 4, 3, 2, 1]', %q{
  counts = []
  counts << Ractor.count
  ractors = (1..3).map { Ractor.new { Ractor.receive } }
  counts << Ractor.count

  ractors[0].send('End 0').join
  sleep 0.1 until ractors[0].inspect =~ /terminated/
  counts << Ractor.count

  ractors[1].send('End 1').join
  sleep 0.1 until ractors[1].inspect =~ /terminated/
  counts << Ractor.count

  ractors[2].send('End 2').join
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
  }.value
}

# ObjectSpace._id2ref can not handle unshareable objects with Ractors
assert_equal 'ok', <<~'RUBY', frozen_string_literal: false
  s = 'hello'

  Ractor.new s.object_id do |id ;s|
    begin
      s = ObjectSpace._id2ref(id)
    rescue => e
      :ok
    end
  end.value
RUBY

# Ractor.make_shareable(obj)
assert_equal 'true', <<~'RUBY', frozen_string_literal: false
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
RUBY

# Ractor.make_shareable(obj) doesn't freeze shareable objects
assert_equal 'true', %q{
  r = Ractor.new{}
  Ractor.make_shareable(a = [r])
  [a.frozen?, a[0].frozen?] == [true, false]
}

# Ractor.make_shareable(a_proc) makes a proc shareable.
assert_equal 'true', %q{
  a = [1, [2, 3], {a: "4"}]

  pr = Ractor.current.instance_eval do
    Proc.new do
      a
    end
  end

  Ractor.make_shareable(a) # referred value should be shareable
  Ractor.make_shareable(pr)
  Ractor.shareable?(pr)
}

# Ractor.make_shareable(a_proc) makes inner structure shareable and freezes it
assert_equal 'true,true,true,true', %q{
  class Proc
    attr_reader :obj
    def initialize
      @obj = Object.new
    end
  end

  pr = Ractor.current.instance_eval do
    Proc.new {}
  end

  results = []
  Ractor.make_shareable(pr)
  results << Ractor.shareable?(pr)
  results << pr.frozen?
  results << Ractor.shareable?(pr.obj)
  results << pr.obj.frozen?
  results.map(&:to_s).join(',')
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

# Ractor.make_shareable with Class/Module
assert_equal '[C, M]', %q{
  class C; end
  module M; end

  Ractor.make_shareable(ary = [C, M])
}

# Ractor.make_shareable with curried proc checks isolation of original proc
assert_equal 'isolation error', %q{
  a = Object.new
  orig = proc { a }
  curried = orig.curry

  begin
    Ractor.make_shareable(curried)
  rescue Ractor::IsolationError
    'isolation error'
  else
    'no error'
  end
}

# define_method() can invoke different Ractor's proc if the proc is shareable.
assert_equal '1', %q{
  class C
    a = 1
    define_method "foo", Ractor.make_shareable(Proc.new{ a })
    a = 2
  end

  Ractor.new{ C.new.foo }.value
}

# Ractor.make_shareable(a_proc) makes a proc shareable.
assert_equal 'can not make a Proc shareable because it accesses outer variables (a).', %q{
  a = b = nil
  pr = Ractor.current.instance_eval do
    Proc.new do
      c = b # assign to a is okay because c is block local variable
      # reading b is okay
      a = b # assign to a is not allowed #=> Ractor::Error
    end
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

# TracePoint with normal Proc should be Ractor local
assert_equal '[6, 10]', %q{
  rs = []
  TracePoint.new(:line){|tp| rs << tp.lineno if tp.path == __FILE__}.enable do
    Ractor.new{ # line 5
      a = 1
      b = 2
    }.value
    c = 3       # line 9
  end
  rs
}

# Ractor deep copies frozen objects (ary)
assert_equal '[true, false]', %q{
  Ractor.new([[]].freeze) { |ary|
    [ary.frozen?, ary.first.frozen? ]
  }.value
}

# Ractor deep copies frozen objects (str)
assert_equal '[true, false]', %q{
  s = String.new.instance_eval { @x = []; freeze}
  Ractor.new(s) { |s|
    [s.frozen?, s.instance_variable_get(:@x).frozen?]
  }.value
}

# Can not trap with not isolated Proc on non-main ractor
assert_equal '[:ok, :ok]', %q{
  a = []
  Ractor.new{
    trap(:INT){p :ok}
  }.join
  a << :ok

  begin
    Ractor.new{
      s = 'str'
      trap(:INT){p s}
    }.join
  rescue => Ractor::RemoteError
    a << :ok
  end
}

# Ractor.select is interruptible
assert_normal_exit %q{
  trap(:INT) do
    exit
  end

  r = Ractor.new do
    loop do
      sleep 1
    end
  end

  Thread.new do
    sleep 0.5
    Process.kill(:INT, Process.pid)
  end
  Ractor.select(r)
}

# Ractor-local storage
assert_equal '[nil, "b", "a"]', %q{
  ans = []
  Ractor.current[:key] = 'a'
  r = Ractor.new{
    Ractor.main << self[:key]
    self[:key] = 'b'
    self[:key]
  }
  ans << Ractor.receive
  ans << r.value
  ans << Ractor.current[:key]
}

assert_equal '1', %q{
  N = 1_000
  Ractor.new{
    a = []
    1_000.times.map{|i|
      Thread.new(i){|i|
        Thread.pass if i < N
        a << Ractor.store_if_absent(:i){ i }
        a << Ractor.current[:i]
      }
    }.each(&:join)
    a.uniq.size
  }.value
}

# Ractor-local storage
assert_equal '2', %q{
  Ractor.new {
    fails = 0
    begin
      Ractor.main[:key] # cannot get ractor local storage from non-main ractor
    rescue => e
      fails += 1 if e.message =~ /Cannot get ractor local/
    end
    begin
      Ractor.main[:key] = 'val'
    rescue => e
      fails += 1 if e.message =~ /Cannot set ractor local/
    end
    fails
  }.value
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
  }.map{|r| r.value}.join
}

assert_equal "ok", %Q{
  N = #{N}
  a, b = 2.times.map{
    Ractor.new{
      N.times.map{|i| -(i.to_s)}
    }
  }.map{|r| r.value}
  N.times do |i|
    unless a[i].equal?(b[i])
      raise [a[i], b[i]].inspect
    end
  end
  :ok
}

# Generic fields_tbl
n = N/2
assert_equal "#{n}#{n}", %Q{
  2.times.map{
    Ractor.new do
      #{n}.times do
        obj = +''
        obj.instance_variable_set("@a", 1)
        obj.instance_variable_set("@b", 1)
        obj.instance_variable_set("@c", 1)
        obj.instance_variable_defined?("@a")
      end
    end
  }.map{|r| r.value}.join
}

# NameError
assert_equal "ok", %q{
  obj = "".freeze # NameError refers the receiver indirectly
  begin
    obj.bar
  rescue => err
  end
  begin
    Ractor.new{} << err
  rescue TypeError
    'ok'
  end
}

assert_equal "ok", %q{
  GC.disable
  Ractor.new {}
  raise "not ok" unless GC.disable

  foo = []
  10.times { foo << 1 }

  GC.start

  'ok'
}

# Can yield back values while GC is sweeping [Bug #18117]
assert_equal "ok", %q{
  port = Ractor::Port.new
  workers = (0...8).map do
    Ractor.new port do |port|
      loop do
        10_000.times.map { Object.new }
        port << Time.now
      end
    end
  end

  1_000.times { port.receive }
  "ok"
} if !yjit_enabled? && ENV['GITHUB_WORKFLOW'] != 'ModGC' # flaky

assert_equal "ok", %q{
  def foo(*); ->{ super }; end
  begin
    Ractor.make_shareable(foo)
  rescue Ractor::IsolationError
    "ok"
  end
}

assert_equal "ok", %q{
  def foo(**); ->{ super }; end
  begin
    Ractor.make_shareable(foo)
  rescue Ractor::IsolationError
    "ok"
  end
}

assert_equal "ok", %q{
  def foo(...); ->{ super }; end
  begin
    Ractor.make_shareable(foo)
  rescue Ractor::IsolationError
    "ok"
  end
}

assert_equal "ok", %q{
  def foo((x), (y)); ->{ super }; end
  begin
    Ractor.make_shareable(foo([], []))
  rescue Ractor::IsolationError
    "ok"
  end
}

# check method cache invalidation
assert_equal "ok", %q{
  module M
    def foo
      @foo
    end
  end

  class A
    include M

    def initialize
      100.times { |i| instance_variable_set(:"@var_#{i}", "bad: #{i}") }
      @foo = 2
    end
  end

  class B
    include M

    def initialize
      @foo = 1
    end
  end

  Ractor.new do
    b = B.new
    100_000.times do
      raise unless b.foo == 1
    end
  end

  a = A.new
  100_000.times do
    raise unless a.foo == 2
  end

  "ok"
}

# check method cache invalidation
assert_equal 'true', %q{
  class C1; def self.foo = 1; end
  class C2; def self.foo = 2; end
  class C3; def self.foo = 3; end
  class C4; def self.foo = 5; end
  class C5; def self.foo = 7; end
  class C6; def self.foo = 11; end
  class C7; def self.foo = 13; end
  class C8; def self.foo = 17; end

  LN = 10_000
  RN = 10
  CS = [C1, C2, C3, C4, C5, C6, C7, C8]
  rs = RN.times.map{|i|
    Ractor.new(CS.shuffle){|cs|
      LN.times.sum{
        cs.inject(1){|r, c| r * c.foo} # c.foo invalidates method cache entry
      }
    }
  }

  n = CS.inject(1){|r, c| r * c.foo} * LN
  rs.map{|r| r.value} == Array.new(RN){n}
}

# check experimental warning
assert_match /\Atest_ractor\.rb:1:\s+warning:\s+Ractor is experimental/, %q{
  Warning[:experimental] = $VERBOSE = true
  STDERR.reopen(STDOUT)
  eval("Ractor.new{}.value", nil, "test_ractor.rb", 1)
}, frozen_string_literal: false

# check moved object
assert_equal 'ok', %q{
  r = Ractor.new do
    Ractor.receive
    GC.start
    :ok
  end

  obj = begin
  raise
  rescue => e
    e = Marshal.load(Marshal.dump(e))
  end

  r.send obj, move: true
  r.value
}

## Ractor::Selector

# Selector#empty? returns true
assert_equal 'true', %q{
  skip true unless defined? Ractor::Selector

  s = Ractor::Selector.new
  s.empty?
}

# Selector#empty? returns false if there is target ractors
assert_equal 'false', %q{
  skip false unless defined? Ractor::Selector

  s = Ractor::Selector.new
  s.add Ractor.new{}
  s.empty?
}

# Selector#clear removes all ractors from the waiting list
assert_equal 'true', %q{
  skip true unless defined? Ractor::Selector

  s = Ractor::Selector.new
  s.add Ractor.new{10}
  s.add Ractor.new{20}
  s.clear
  s.empty?
}

# Selector#wait can wait multiple ractors
assert_equal '[10, 20, true]', %q{
  skip [10, 20, true] unless defined? Ractor::Selector

  s = Ractor::Selector.new
  s.add Ractor.new{10}
  s.add Ractor.new{20}
  r, v = s.wait
  vs = []
  vs << v
  r, v = s.wait
  vs << v
  [*vs.sort, s.empty?]
} if defined? Ractor::Selector

# Selector#wait can wait multiple ractors with receiving.
assert_equal '30', %q{
  skip 30 unless defined? Ractor::Selector

  RN = 30
  rs = RN.times.map{
    Ractor.new{ :v }
  }
  s = Ractor::Selector.new(*rs)

  results = []
  until s.empty?
    results << s.wait

    # Note that s.wait can raise an exception because other Ractors/Threads
    # can take from the same ractors in the waiting set.
    # In this case there is no other takers so `s.wait` doesn't raise an error.
  end

  results.size
} if defined? Ractor::Selector

# Selector#wait can support dynamic addition
assert_equal '600', %q{
  skip 600 unless defined? Ractor::Selector

  RN = 100
  s = Ractor::Selector.new
  port = Ractor::Port.new
  rs = RN.times.map{
    Ractor.new{
      Ractor.main << Ractor.new(port){|port| port << :v3; :v4 }
      Ractor.main << Ractor.new(port){|port| port << :v5; :v6 }
      Ractor.yield :v1
      :v2
    }
  }

  rs.each{|r| s.add(r)}
  h = {v1: 0, v2: 0, v3: 0, v4: 0, v5: 0, v6: 0}

  loop do
    case s.wait receive: true
    in :receive, r
      s.add r
    in r, v
      h[v] += 1
      break if h.all?{|k, v| v == RN}
    end
  end

  h.sum{|k, v| v}
} unless yjit_enabled? # http://ci.rvm.jp/results/trunk-yjit@ruby-sp2-docker/4466770

# Selector should be GCed (free'ed) without trouble
assert_equal 'ok', %q{
  skip :ok unless defined? Ractor::Selector

  RN = 30
  rs = RN.times.map{
    Ractor.new{ :v }
  }
  s = Ractor::Selector.new(*rs)
  :ok
}

end # if !ENV['GITHUB_WORKFLOW']

# Chilled strings are not shareable
assert_equal 'false', %q{
  Ractor.shareable?("chilled")
}

# Chilled strings can be made shareable
assert_equal 'true', %q{
  shareable = Ractor.make_shareable("chilled")
  shareable == "chilled" && Ractor.shareable?(shareable)
}

# require in Ractor
assert_equal 'true', %q{
  Module.new do
    def require feature
      return Ractor._require(feature) unless Ractor.main?
      super
    end
    Object.prepend self
    set_temporary_name 'Ractor#require'
  end

  Ractor.new{
    begin
      require 'tempfile'
      Tempfile.new
    rescue SystemStackError
      # prism parser with -O0 build consumes a lot of machine stack
      Data.define(:fileno).new(1)
    end
  }.value.fileno > 0
}

# require_relative in Ractor
assert_equal 'true', %q{
  dummyfile = File.join(__dir__, "dummy#{rand}.rb")
  return true if File.exist?(dummyfile)

  begin
    File.write dummyfile, ''
  rescue Exception
    # skip on any errors
    return true
  end

  begin
    Ractor.new dummyfile do |f|
      require_relative File.basename(f)
    end.value
  ensure
    File.unlink dummyfile
  end
}

# require_relative in Ractor
assert_equal 'LoadError', %q{
  dummyfile = File.join(__dir__, "not_existed_dummy#{rand}.rb")
  return true if File.exist?(dummyfile)

  Ractor.new dummyfile do |f|
    begin
      require_relative File.basename(f)
    rescue LoadError => e
      e.class
    end
  end.value
}

# autolaod in Ractor
assert_equal 'true', %q{
  autoload :Tempfile, 'tempfile'

  r = Ractor.new do
    begin
      Tempfile.new
    rescue SystemStackError
      # prism parser with -O0 build consumes a lot of machine stack
      Data.define(:fileno).new(1)
    end
  end
  r.value.fileno > 0
}

# failed in autolaod in Ractor
assert_equal 'LoadError', %q{
  dummyfile = File.join(__dir__, "not_existed_dummy#{rand}.rb")
  autoload :Tempfile, dummyfile

  r = Ractor.new do
    begin
      Tempfile.new
    rescue LoadError => e
      e.class
    end
  end
  r.value
}

# bind_call in Ractor [Bug #20934]
assert_equal 'ok', %q{
  2.times.map do
    Ractor.new do
      1000.times do
        Object.instance_method(:itself).bind_call(self)
      end
    end
  end.each(&:join)
  GC.start
  :ok.itself
}

# moved objects being corrupted if embeded (String)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = "foobarbazfoobarbazfoobarbazfoobarbaz"
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.value
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (Array)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = Array.new(10, 42)
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.value
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (Hash)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = { foo: 1, bar: 2 }
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.value
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (MatchData)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = "foo".match(/o/)
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.value
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (Struct)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = Struct.new(:a, :b, :c, :d, :e, :f).new(1, 2, 3, 4, 5, 6)
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.value
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (Object)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  class SomeObject
    attr_reader :a, :b, :c, :d, :e, :f
    def initialize
      @a = @b = @c = @d = @e = @f = 1
    end

    def ==(o)
      @a == o.a &&
      @b == o.b &&
      @c == o.c &&
      @d == o.d &&
      @e == o.e &&
      @f == o.f
    end
  end

  SomeObject.new # initial non-embeded

  obj = SomeObject.new
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.value
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved arrays can't be used
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = [1]
  ractor.send(obj, move: true)
  begin
    [].concat(obj)
  rescue TypeError
    :ok
  else
    :fail
  end
}

# moved strings can't be used
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = "hello"
  ractor.send(obj, move: true)
  begin
    "".replace(obj)
  rescue TypeError
    :ok
  else
    :fail
  end
}

# moved hashes can't be used
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = { a: 1 }
  ractor.send(obj, move: true)
  begin
    {}.merge(obj)
  rescue TypeError
    :ok
  else
    :fail
  end
}

# move objects inside frozen containers
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = Array.new(10, 42)
  original = obj.dup
  ractor.send([obj].freeze, move: true)
  roundtripped_obj = ractor.value[0]
  roundtripped_obj == original ? :ok : roundtripped_obj
}

# move object with generic ivar
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = Array.new(10, 42)
  obj.instance_variable_set(:@array, [1])

  ractor.send(obj, move: true)
  roundtripped_obj = ractor.value
  roundtripped_obj.instance_variable_get(:@array) == [1] ? :ok : roundtripped_obj
}

# moved composite types move their non-shareable parts properly
assert_equal 'ok', %q{
  k, v = String.new("key"), String.new("value")
  h = { k => v }
  h.instance_variable_set("@b", String.new("b"))
  a = [k,v]
  o_singleton = Object.new
  def o_singleton.a
    @a
  end
  o_singleton.instance_variable_set("@a", String.new("a"))
  class MyObject
    attr_reader :a
    def initialize(a)
      @a = a
    end
  end
  struct_class = Struct.new(:a)
  struct = struct_class.new(String.new('a'))
  o = MyObject.new(String.new('a'))
  port = Ractor::Port.new

  r = Ractor.new port do |port|
    loop do
      obj = Ractor.receive
      val = case obj
      when Hash
        obj['key'] == 'value' && obj.instance_variable_get("@b") == 'b'
      when Array
        obj[0] == 'key'
      when Struct
        obj.a == 'a'
      when Object
        obj.a == 'a'
      end
      port << val
    end
  end

  objs = [h, a, o_singleton, o, struct]
  objs.each_with_index do |obj, i|
    klass = obj.class
    parts_moved = {}
    case obj
    when Hash
      parts_moved[klass] = [obj['key'], obj.instance_variable_get("@b")]
    when Array
      parts_moved[klass] = obj.dup # the contents
    when Struct, Object
      parts_moved[klass] = [obj.a]
    end
    r.send(obj, move: true)
    val = port.receive
    if val != true
      raise "bad val in ractor for obj at i:#{i}"
    end
    begin
      p obj
    rescue
    else
      raise "should be moved"
    end
    parts_moved.each do |klass, parts|
      parts.each_with_index do |part, j|
        case part
        when Ractor::MovedObject
        else
          raise "part for class #{klass} at i:#{j} should be moved"
        end
      end
    end
  end
  'ok'
}

# fork after creating Ractor
assert_equal 'ok', %q{
begin
  Ractor.new { Ractor.receive }
  _, status = Process.waitpid2 fork { }
  status.success? ? "ok" : status
rescue NotImplementedError
  :ok
end
}

# Ractors should be terminated after fork
assert_equal 'ok', %q{
begin
  r = Ractor.new { Ractor.receive }
  _, status = Process.waitpid2 fork {
    begin
      raise if r.value != nil
    end
  }
  r.send(123)
  raise unless r.value == 123
  status.success? ? "ok" : status
rescue NotImplementedError
  :ok
end
}

# Ractors should be terminated after fork
assert_equal 'ok', %q{
begin
  r = Ractor.new { Ractor.receive }
  _, status = Process.waitpid2 fork {
    begin
      r.send(123)
    rescue Ractor::ClosedError
    end
  }
  r.send(123)
  raise unless r.value == 123
  status.success? ? "ok" : status
rescue NotImplementedError
  :ok
end
}

# Creating classes inside of Ractors
# [Bug #18119]
assert_equal 'ok', %q{
  port = Ractor::Port.new
  workers = (0...8).map do
    Ractor.new port do |port|
      loop do
        100.times.map { Class.new }
        port << nil
      end
    end
  end

  100.times { port.receive }

  'ok'
}

# Using Symbol#to_proc inside ractors
# [Bug #21354]
assert_equal 'ok', %q{
  :inspect.to_proc
  Ractor.new do
    # It should not use this cached proc, it should create a new one. If it used
    # the cached proc, we would get a ractor_confirm_belonging error here.
    :inspect.to_proc
  end.join
  'ok'
}

# take vm lock when deleting generic ivars from the global table
assert_equal 'ok', %q{
  Ractor.new do
    a = [1, 2, 3]
    a.object_id
    a.dup # this deletes generic ivar on dupped object
    'ok'
  end.value
}

## Ractor#monitor

# monitor port returns `:exited` when the monitering Ractor terminated.
assert_equal 'true', %q{
  r = Ractor.new do
    Ractor.main << :ok1
    :ok2
  end

  r.monitor port = Ractor::Port.new
  Ractor.receive # :ok1
  port.receive == :exited
}

# monitor port returns `:exited` even if the monitoring Ractor was terminated.
assert_equal 'true', %q{
  r = Ractor.new do
    :ok
  end

  r.join # wait for r's terminateion

  r.monitor port = Ractor::Port.new
  port.receive == :exited
}

# monitor returns false if the monitoring Ractor was terminated.
assert_equal 'false', %q{
  r = Ractor.new do
    :ok
  end

  r.join # wait for r's terminateion

  r.monitor Ractor::Port.new
}

# monitor port returns `:aborted` when the monitering Ractor is aborted.
assert_equal 'true', %q{
  r = Ractor.new do
    Ractor.main << :ok1
    raise 'ok'
  end

  r.monitor port = Ractor::Port.new
  Ractor.receive # :ok1
  port.receive == :aborted
}

# monitor port returns `:aborted` even if the monitoring Ractor was aborted.
assert_equal 'true', %q{
  r = Ractor.new do
    raise 'ok'
  end

  begin
    r.join # wait for r's terminateion
  rescue Ractor::RemoteError
    # ignore
  end

  r.monitor port = Ractor::Port.new
  port.receive == :aborted
}

## Ractor#join

# Ractor#join returns self when the Ractor is terminated.
assert_equal 'true', %q{
  r = Ractor.new do
    Ractor.receive
  end

  r << :ok
  r.join
  r.inspect in /terminated/
} if false # TODO

# Ractor#join raises RemoteError when the remote Ractor aborted with an exception
assert_equal 'err', %q{
  r = Ractor.new do
    raise 'err'
  end

  begin
    r.join
  rescue Ractor::RemoteError => e
    e.cause.message
  end
}

## Ractor#value

# Ractor#value returns the last expression even if it is unshareable
assert_equal 'true', %q{
  r = Ractor.new do
    obj = [1, 2]
    obj << obj.object_id
  end

  ret = r.value
  ret == [1, 2, ret.object_id]
}

# Only one Ractor can call Ractor#value
assert_equal '[["Only the successor ractor can take a value", 9], ["ok", 2]]', %q{
  r = Ractor.new do
    'ok'
  end

  RN = 10

  rs = RN.times.map do
    Ractor.new r do |r|
      begin
        Ractor.main << r.value
        Ractor.main << r.value # this ractor can get same result
      rescue Ractor::Error => e
        Ractor.main << e.message
      end
    end
  end

  (RN+1).times.map{
    Ractor.receive
  }.tally.sort
}

# Ractor#take will warn for compatibility.
# This method will be removed after 2025/09/01
assert_equal "2", %q{
  raise "remove Ractor#take and this test" if Time.now > Time.new(2025, 9, 2)
  $VERBOSE = true
  r = Ractor.new{42}
  $msg = []
  def Warning.warn(msg)
    $msg << msg
  end
  r.take
  r.take
  raise unless $msg.all?{/Ractor#take/ =~ it}
  $msg.size
}
