require 'test/unit'

require 'drb/drb'
require 'drb/eq'
require 'rinda/tuplespace'

require 'singleton'

module Rinda

class MockClock
  include Singleton

  class MyTS < Rinda::TupleSpace
    def keeper_thread
      nil
    end
  end
  
  def initialize
    @now = 2
    @reso = 1
    @ts = MyTS.new
    @ts.write([2, :now])
    @inf = 2**31 - 1
  end

  def now
    @now.to_f
  end

  def at(n)
    n
  end
    
  def _forward(n=nil)
    now ,= @ts.take([nil, :now])
    @now = now + n
    n = @reso if n.nil?
    @ts.write([@now, :now])
  end

  def forward(n)
    while n > 0
      _forward(@reso)
      n -= @reso
      Thread.pass
    end
  end

  def rewind
    now ,= @ts.take([nil, :now])
    @ts.write([@inf, :now])
    @ts.take([nil, :now])
    @now = 2
    @ts.write([2, :now])
  end

  def sleep(n=nil)
    now ,= @ts.read([nil, :now])
    @ts.read([(now + n)..@inf, :now])
    0
  end
end

module Time
  def sleep(n)
    @m.sleep(n)
  end
  module_function :sleep

  def at(n)
    n
  end
  module_function :at

  def now
    @m ? @m.now : 2
  end
  module_function :now

  def rewind
    @m.rewind
  end
  module_function :rewind

  def forward(n)
    @m.forward(n)
  end
  module_function :forward

  @m = MockClock.instance
end

class TupleSpace
  def sleep(n)
    Time.sleep(n)
  end
end

module TupleSpaceTestModule
  def sleep(n)
    if Thread.current == Thread.main
      Time.forward(n)
    else
      Time.sleep(n)
    end
  end

  def thread_join(th)
    while th.alive?
      Kernel.sleep(0.1)
      sleep(1)
    end
    th.value
  end
  
  def test_00_tuple
    tuple = Rinda::TupleEntry.new([1,2,3])
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
  end

  def test_00_template
    tmpl = Rinda::Template.new([1,2,3])
    assert_equal(3, tmpl.size)
    assert_equal(3, tmpl[2])
    assert(tmpl.match([1,2,3]))
    assert(!tmpl.match([1,nil,3]))

    tmpl = Rinda::Template.new([/^rinda/i, nil, :hello])
    assert_equal(3, tmpl.size)
    assert(tmpl.match(['Rinda', 2, :hello]))
    assert(!tmpl.match(['Rinda', 2, Symbol]))
    assert(!tmpl.match([1, 2, :hello]))
    assert(tmpl.match([/^rinda/i, 2, :hello]))

    tmpl = Rinda::Template.new([Symbol])
    assert_equal(1, tmpl.size)
    assert(tmpl.match([:hello]))
    assert(tmpl.match([Symbol]))
    assert(!tmpl.match(['Symbol']))

    tmpl = Rinda::Template.new({"message"=>String, "name"=>String})
    assert_equal(2, tmpl.size)
    assert(tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    assert_raises(Rinda::InvalidHashTupleKey) do
      tmpl = Rinda::Template.new({:message=>String, "name"=>String})
    end
    tmpl = Rinda::Template.new({"name"=>String})
    assert_equal(1, tmpl.size)
    assert(tmpl.match({"name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>:symbol, "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    tmpl = Rinda::Template.new({"message"=>String, "name"=>String})
    assert_equal(2, tmpl.size)
    assert(tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    tmpl = Rinda::Template.new({"message"=>String})
    assert_equal(1, tmpl.size)
    assert(tmpl.match({"message"=>"Hello"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    tmpl = Rinda::Template.new({"message"=>String, "name"=>nil})
    assert_equal(2, tmpl.size)
    assert(tmpl.match({"message"=>"Hello", "name"=>"Foo"}))
    assert(!tmpl.match({"message"=>"Hello", "name"=>"Foo", "1"=>2}))
    assert(!tmpl.match({"message"=>"Hi", "name"=>"Foo", "age"=>1}))
    assert(!tmpl.match({"message"=>"Hello", "no_name"=>"Foo"}))

    assert_raises(Rinda::InvalidHashTupleKey) do
      @ts.write({:message=>String, "name"=>String})
    end

    @ts.write([1, 2, 3])
    assert_equal([1, 2, 3], @ts.take([1, 2, 3]))

    @ts.write({'1'=>1, '2'=>2, '3'=>3})
    assert_equal({'1'=>1, '2'=>2, '3'=>3}, @ts.take({'1'=>1, '2'=>2, '3'=>3}))

    entry = @ts.write(['1'=>1, '2'=>2, '3'=>3])
    assert_raises(Rinda::RequestExpiredError) do
      assert_equal({'1'=>1, '2'=>2, '3'=>3}, @ts.read({'1'=>1}, 0))
    end
    entry.cancel
  end

  def test_00_DRbObject
    ro = DRbObject.new(nil, "druby://host:1234")
    tmpl = Rinda::DRbObjectTemplate.new
    assert(tmpl === ro)

    tmpl = Rinda::DRbObjectTemplate.new("druby://host:1234")
    assert(tmpl === ro)

    tmpl = Rinda::DRbObjectTemplate.new("druby://host:12345")
    assert(!(tmpl === ro))

    tmpl = Rinda::DRbObjectTemplate.new(/^druby:\/\/host:/)
    assert(tmpl === ro)

    ro = DRbObject.new_with(12345, 1234)
    assert(!(tmpl === ro))

    ro = DRbObject.new_with("druby://foo:12345", 1234)
    assert(!(tmpl === ro))

    tmpl = Rinda::DRbObjectTemplate.new(/^druby:\/\/(foo|bar):/)
    assert(tmpl === ro)

    ro = DRbObject.new_with("druby://bar:12345", 1234)
    assert(tmpl === ro)

    ro = DRbObject.new_with("druby://baz:12345", 1234)
    assert(!(tmpl === ro))
  end

  def test_inp_rdp
    assert_raises(Rinda::RequestExpiredError) do
      @ts.take([:empty], 0)
    end

    assert_raises(Rinda::RequestExpiredError) do
      @ts.read([:empty], 0)
    end
  end

  def test_ruby_talk_264062
    th = Thread.new { @ts.take([:empty], 1) }
    sleep(10)
    assert_raises(Rinda::RequestExpiredError) do
      thread_join(th)
    end

    th = Thread.new { @ts.read([:empty], 1) }
    sleep(10)
    assert_raises(Rinda::RequestExpiredError) do
      thread_join(th)
    end
  end

  def test_symbol_tuple
    @ts.write([:symbol, :symbol])
    @ts.write(['string', :string])
    assert_equal([[:symbol, :symbol]], @ts.read_all([:symbol, nil]))
    assert_equal([[:symbol, :symbol]], @ts.read_all([Symbol, nil]))
    assert_equal([], @ts.read_all([:nil, nil]))
  end

  def test_core_01
    5.times do |n|
      @ts.write([:req, 2])
    end

    assert_equal([[:req, 2], [:req, 2], [:req, 2], [:req, 2], [:req, 2]],
		 @ts.read_all([nil, nil]))

    taker = Thread.new do
      s = 0
      while true
	begin
	  tuple = @ts.take([:req, Integer], 1)
	  assert_equal(2, tuple[1])
	  s += tuple[1]
	rescue Rinda::RequestExpiredError
	  break
	end
      end
      @ts.write([:ans, s])
      s
    end
    
    assert_equal(10, thread_join(taker))
    tuple = @ts.take([:ans, nil])
    assert_equal(10, tuple[1])
  end

  def test_core_02
    taker = Thread.new do
      s = 0
      while true
	begin
	  tuple = @ts.take([:req, Integer], 1)
	  assert_equal(2, tuple[1])
	  s += tuple[1]
	rescue Rinda::RequestExpiredError
	  break
	end
      end
      @ts.write([:ans, s])
      s
    end

    5.times do |n|
      @ts.write([:req, 2])
    end

    assert_equal(10, thread_join(taker))
    tuple = @ts.take([:ans, nil])
    assert_equal(10, tuple[1])
    assert_equal([], @ts.read_all([nil, nil]))
  end
  
  def test_core_03_notify
    notify1 = @ts.notify(nil, [:req, Integer])
    notify2 = @ts.notify(nil, [:ans, Integer], 8)
    notify3 = @ts.notify(nil, {"message"=>String, "name"=>String}, 8)

    @ts.write({"message"=>"first", "name"=>"3"}, 3)
    @ts.write({"message"=>"second", "name"=>"1"}, 1)
    @ts.write({"message"=>"third", "name"=>"0"})
    @ts.take({"message"=>"third", "name"=>"0"})

    listener1 = Thread.new do
      lv = 0
      n = 0
      notify1.each  do |ev, tuple|
	n += 1
	if ev == 'write'
	  lv = lv + 1
	elsif ev == 'take'
	  lv = lv - 1
	else
	  break
	end
	assert(lv >= 0)
	assert_equal([:req, 2], tuple)
      end
      [lv, n]
    end

    listener2 = Thread.new do
      result = nil
      lv = 0
      n = 0
      notify2.each do |ev, tuple|
	n += 1
	if ev == 'write'
	  lv = lv + 1
	elsif ev == 'take'
	  lv = lv - 1
	elsif ev == 'close'
	  result = [lv, n]
	else
	  break
	end
	assert(lv >= 0)
	assert_equal([:ans, 10], tuple)
      end
      result
    end

    taker = Thread.new do
      s = 0
      while true
	begin
	  tuple = @ts.take([:req, Integer], 1)
	  s += tuple[1]
	rescue Rinda::RequestExpiredError
	  break
	end
      end
      @ts.write([:ans, s])
      s
    end

    5.times do |n|
      @ts.write([:req, 2])
    end

    @ts.take({"message"=>"first", "name"=>"3"})

    sleep(4)
    assert_equal(10, thread_join(taker))
    # notify2 must not expire until this @ts.take.
    # sleep(4) might be short enough for the timeout of notify2 (8 secs)
    tuple = @ts.take([:ans, nil])
    assert_equal(10, tuple[1])
    assert_equal([], @ts.read_all([nil, nil]))

    notify1.cancel
    sleep(7) # notify2 expired (sleep(4)+sleep(7) > 8)

    assert_equal([0, 11], thread_join(listener1))
    assert_equal([0, 3], thread_join(listener2))

    ary = []
    ary.push(["write", {"message"=>"first", "name"=>"3"}])
    ary.push(["write", {"message"=>"second", "name"=>"1"}])
    ary.push(["write", {"message"=>"third", "name"=>"0"}])
    ary.push(["take", {"message"=>"third", "name"=>"0"}])
    ary.push(["take", {"message"=>"first", "name"=>"3"}])
    ary.push(["delete", {"message"=>"second", "name"=>"1"}])
    ary.push(["close"])

    notify3.each do |ev|
      assert_equal(ary.shift, ev)
    end
    assert_equal([], ary)
  end

  def test_cancel_01
    entry = @ts.write([:removeme, 1])
    assert_equal([[:removeme, 1]], @ts.read_all([nil, nil]))
    entry.cancel
    assert_equal([], @ts.read_all([nil, nil]))
    
    template = nil
    taker = Thread.new do
      @ts.take([:take, nil], 10) do |template|
	Thread.new do
	  template.cancel
	end
      end
    end
    
    sleep(2)

    assert_raises(Rinda::RequestCanceledError) do
      assert_nil(thread_join(taker))
    end

    assert(template.canceled?)
    
    @ts.write([:take, 1])

    assert_equal([[:take, 1]], @ts.read_all([nil, nil]))
  end

  def test_cancel_02
    entry = @ts.write([:removeme, 1])
    assert_equal([[:removeme, 1]], @ts.read_all([nil, nil]))
    entry.cancel
    assert_equal([], @ts.read_all([nil, nil]))

    template = nil
    reader = Thread.new do
      @ts.read([:take, nil], 10) do |template|
	Thread.new do
	  template.cancel
	end
      end
    end

    sleep(2)

    assert_raises(Rinda::RequestCanceledError) do
      assert_nil(thread_join(reader))
    end

    assert(template.canceled?)
    
    @ts.write([:take, 1])

    assert_equal([[:take, 1]], @ts.read_all([nil, nil]))
  end

  class SimpleRenewer
    def initialize(sec, n = 1)
      @sec = sec
      @n = n
    end
    
    def renew
      return -1 if @n <= 0
      @n -= 1
      return @sec
    end
  end

  def test_00_renewer
    tuple = Rinda::TupleEntry.new([1,2,3], true)
    assert(!tuple.canceled?)
    assert(tuple.expired?)
    assert(!tuple.alive?)
    
    tuple = Rinda::TupleEntry.new([1,2,3], 1)
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
    sleep(2)
    assert(tuple.expired?)
    assert(!tuple.alive?)

    @renewer = SimpleRenewer.new(1,2)
    tuple = Rinda::TupleEntry.new([1,2,3], @renewer)
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
    sleep(1)
    assert(!tuple.canceled?)
    assert(!tuple.expired?)
    assert(tuple.alive?)
    sleep(2)
    assert(tuple.expired?)
    assert(!tuple.alive?)
  end
end

class TupleSpaceTest < Test::Unit::TestCase
  include TupleSpaceTestModule

  def setup
    ThreadGroup.new.add(Thread.current)
    @ts = Rinda::TupleSpace.new(1)
  end
end

class TupleSpaceProxyTest < Test::Unit::TestCase
  include TupleSpaceTestModule

  def setup
    ThreadGroup.new.add(Thread.current)
    @ts_base = Rinda::TupleSpace.new(1)
    @ts = Rinda::TupleSpaceProxy.new(@ts_base)
  end

  def test_remote_array_and_hash
    @ts.write(DRbObject.new([1, 2, 3]))
    assert_equal([1, 2, 3], @ts.take([1, 2, 3], 0))
    @ts.write(DRbObject.new({'head' => 1, 'tail' => 2}))
    assert_equal({'head' => 1, 'tail' => 2},
                 @ts.take({'head' => 1, 'tail' => 2}, 0))
  end

  @server = DRb.primary_server || DRb.start_service
end

end

