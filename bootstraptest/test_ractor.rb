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

# dtoa race condition
assert_equal '[:ok, :ok, :ok]', %q{
  n = 3
  n.times.map{
    Ractor.new{
      10_000.times{ rand.to_s }
      :ok
    }
  }.map(&:take)
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
} unless (ENV.key?('TRAVIS') && ENV['TRAVIS_CPU_ARCH'] == 'arm64') # https://bugs.ruby-lang.org/issues/17878

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

# Ractor.main returns main ractor
assert_equal 'true', %q{
  Ractor.new{
    Ractor.main
  }.take == Ractor.current
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
} unless /mswin/ =~ RUBY_PLATFORM # randomly hangs on mswin https://github.com/ruby/ruby/actions/runs/3753871445/jobs/6377551069#step:20:131

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
  taken = []
  yielded = []
  until received.size == RN && taken.size == RN && yielded.size == RN
    r, v = Ractor.select(CR, *rs, yield_value: 'yield')
    case r
    when :receive
      received << v
    when :yield
      yielded << v
    else
      taken << v
      rs.delete r
    end
  end
  r = [received == ['sendyield'] * RN,
       yielded  == [nil] * RN,
       taken    == ['take'] * RN,
  ]

  STDERR.puts [received, yielded, taken].inspect
  r
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
assert_equal "ok", <<~'RUBY', frozen_string_literal: false
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
    end.take

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
  modified = r.take

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
  a2 = r.take
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
r.take[:frozen]
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

# yield/move should not make moved object when the yield is not succeeded
assert_equal '"str"', %q{
  R = Ractor.new{}
  M = Ractor.current
  r = Ractor.new do
    s = 'str'
    selected_r, v = Ractor.select R, yield_value: s, move: true
    raise if selected_r != R # taken from R
    M.send s.inspect # s should not be a moved object
  end

  Ractor.receive
}

# yield/move can fail
assert_equal "allocator undefined for Thread", %q{
  r = Ractor.new do
    obj = Thread.new{}
    Ractor.yield obj
  rescue => e
    e.message
  end
  r.take
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

# $stdin,out,err belong to Ractor
assert_equal 'ok', %q{
  r = Ractor.new do
    $stdin.itself
    $stdout.itself
    $stderr.itself
    'ok'
  end

  r.take
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
    r.take
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

  a = Ractor.new{ C.int }.take
  b = Ractor.new do
    C.str.to_i
  rescue Ractor::IsolationError
    10
  end.take
  c = Ractor.new do
    C.fstr.to_i
  end.take

  d = Ractor.new{ M.int }.take
  e = Ractor.new do
    M.str.to_i
  rescue Ractor::IsolationError
    20
  end.take
  f = Ractor.new do
    M.fstr.to_i
  end.take


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
  }.take
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
values = r.take
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
    r.take
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
    r.take
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
    r.take
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
    Ractor.new{ str() }.take
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
    r.take
  rescue Ractor::RemoteError => e
    e.cause.message
  end
RUBY

# define_method is not allowed
assert_equal "defined with an un-shareable Proc in a different Ractor", %q{
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
assert_equal 'ok', <<~'RUBY', frozen_string_literal: false
  s = 'hello'

  Ractor.new s.object_id do |id ;s|
    begin
      s = ObjectSpace._id2ref(id)
    rescue => e
      :ok
    end
  end.take
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

  Ractor.new{ C.new.foo }.take
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
    }.take
    c = 3       # line 9
  end
  rs
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
    Ractor.yield self[:key]
    self[:key] = 'b'
    self[:key]
  }
  ans << r.take
  ans << r.take
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
  }.take
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
  }.take
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

assert_equal "ok", %Q{
  N = #{N}
  a, b = 2.times.map{
    Ractor.new{
      N.times.map{|i| -(i.to_s)}
    }
  }.map{|r| r.take}
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
  }.map{|r| r.take}.join
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
  workers = (0...8).map do
    Ractor.new do
      loop do
        10_000.times.map { Object.new }
        Ractor.yield Time.now
      end
    end
  end

  1_000.times { idle_worker, tmp_reporter = Ractor.select(*workers) }
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
  rs.map{|r| r.take} == Array.new(RN){n}
}

# check experimental warning
assert_match /\Atest_ractor\.rb:1:\s+warning:\s+Ractor is experimental/, %q{
  Warning[:experimental] = $VERBOSE = true
  STDERR.reopen(STDOUT)
  eval("Ractor.new{}.take", nil, "test_ractor.rb", 1)
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
  r.take
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
  rs = RN.times.map{
    Ractor.new{
      Ractor.main << Ractor.new{ Ractor.yield :v3; :v4 }
      Ractor.main << Ractor.new{ Ractor.yield :v5; :v6 }
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
  }.take.fileno > 0
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
    end.take
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
  end.take
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
  r.take.fileno > 0
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
  r.take
}

# bind_call in Ractor [Bug #20934]
assert_equal 'ok', %q{
  2.times.map do
    Ractor.new do
      1000.times do
        Object.instance_method(:itself).bind_call(self)
      end
    end
  end.each(&:take)
  GC.start
  :ok.itself
}

# moved objects being corrupted if embeded (String)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = "foobarbazfoobarbazfoobarbazfoobarbaz"
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.take
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (Array)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = Array.new(10, 42)
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.take
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (Hash)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = { foo: 1, bar: 2 }
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.take
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (MatchData)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = "foo".match(/o/)
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.take
  roundtripped_obj == obj ? :ok : roundtripped_obj
}

# moved objects being corrupted if embeded (Struct)
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = Struct.new(:a, :b, :c, :d, :e, :f).new(1, 2, 3, 4, 5, 6)
  ractor.send(obj.dup, move: true)
  roundtripped_obj = ractor.take
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
  roundtripped_obj = ractor.take
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
  roundtripped_obj = ractor.take[0]
  roundtripped_obj == original ? :ok : roundtripped_obj
}

# move object with generic ivar
assert_equal 'ok', %q{
  ractor = Ractor.new { Ractor.receive }
  obj = Array.new(10, 42)
  obj.instance_variable_set(:@array, [1])

  ractor.send(obj, move: true)
  roundtripped_obj = ractor.take
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
  r = Ractor.new do
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
      Ractor.yield val
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
    val = r.take
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
      r.take
      raise "ng"
    rescue Ractor::ClosedError
    end
  }
  r.send(123)
  raise unless r.take == 123
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
      raise "ng"
    rescue Ractor::ClosedError
    end
  }
  r.send(123)
  raise unless r.take == 123
  status.success? ? "ok" : status
rescue NotImplementedError
  :ok
end
}

# Creating classes inside of Ractors
# [Bug #18119]
assert_equal 'ok', %q{
  workers = (0...8).map do
    Ractor.new do
      loop do
        100.times.map { Class.new }
        Ractor.yield nil
      end
    end
  end

  100.times { Ractor.select(*workers) }

  'ok'
}

# [Bug #20905] Scheduler tests
assert_equal 'success', %q{
  def counter_loop
    counter = 0
    counter += 1 while counter < 3_000_000
  end
  ractors = 5.times.map { Ractor.new { Thread.new { counter_loop }; counter_loop } }
  counter_loop
  while ractors.any?
    r, obj = Ractor.select(*ractors)
    if r
      ractors.delete(r)
    end
  end
  'success'
}
