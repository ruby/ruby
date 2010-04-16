require 'test/unit'
require 'soap/property'


module SOAP


class TestProperty < Test::Unit::TestCase
  FrozenError = (RUBY_VERSION >= "1.9.0") ? RuntimeError : TypeError

  def setup
    @prop = ::SOAP::Property.new
  end

  def teardown
    # Nothing to do.
  end

  def test_s_load
    propstr = <<__EOP__

# comment1

# comment2\r
# comment2

\r
a.b.0 = 1
a.b.1 = 2
a.b.2 = 3
client.protocol.http.proxy=http://myproxy:8080   \r
client.protocol.http.no_proxy:  intranet.example.com,local.example.com\r
client.protocol.http.protocol_version = 1.0
foo\\:bar\\=baz = qux
foo\\\\.bar.baz=\tq\\\\ux\ttab
  a\\ b                            =                          1
[ppp.qqq.rrr]
sss = 3
ttt.uuu = 4

[ sss.ttt.uuu  ]
vvv.www = 5
[  ]
xxx.yyy.zzz = 6
__EOP__
    prop = Property.load(propstr)
    assert_equal(["1", "2", "3"], prop["a.b"].values.sort)
    assert_equal("intranet.example.com,local.example.com",
      prop["client.protocol.http.no_proxy"])
    assert_equal("http://myproxy:8080", prop["client.protocol.http.proxy"])
    assert_equal("1.0", prop["client.protocol.http.protocol_version"])
    assert_equal("q\\ux\ttab", prop['foo\.bar.baz'])
    assert_equal("1", prop['a b'])
    assert_equal("3", prop['ppp.qqq.rrr.sss'])
    assert_equal("4", prop['ppp.qqq.rrr.ttt.uuu'])
    assert_equal("5", prop['sss.ttt.uuu.vvv.www'])
    assert_equal("6", prop['xxx.yyy.zzz'])
  end

  def test_load
    prop = Property.new
    hooked = false
    prop.add_hook("foo.bar.baz") do |name, value|
      assert_equal(["foo", "bar", "baz"], name)
      assert_equal("123", value)
      hooked = true
    end
    prop.lock
    prop["foo.bar"].lock
    prop.load("foo.bar.baz = 123")
    assert(hooked)
    assert_raises(FrozenError) do
      prop.load("foo.bar.qux = 123")
    end
    prop.load("foo.baz = 456")
    assert_equal("456", prop["foo.baz"])
  end

  def test_initialize
    prop = ::SOAP::Property.new
    # store is empty
    assert_nil(prop["a"])
    # does hook work?
    assert_equal(1, prop["a"] = 1)
  end

  def test_aref
    # name_to_a
    assert_nil(@prop[:foo])
    assert_nil(@prop["foo"])
    assert_nil(@prop[[:foo]])
    assert_nil(@prop[["foo"]])
    assert_raises(ArgumentError) do
      @prop[1]
    end
    @prop[:foo] = :foo
    assert_equal(:foo, @prop[:foo])
    assert_equal(:foo, @prop["foo"])
    assert_equal(:foo, @prop[[:foo]])
    assert_equal(:foo, @prop[["foo"]])
  end

  def test_referent
    # referent(1)
    assert_nil(@prop["foo.foo"])
    assert_nil(@prop[["foo", "foo"]])
    assert_nil(@prop[["foo", :foo]])
    @prop["foo.foo"] = :foo
    assert_equal(:foo, @prop["foo.foo"])
    assert_equal(:foo, @prop[["foo", "foo"]])
    assert_equal(:foo, @prop[[:foo, "foo"]])
    # referent(2)
    @prop["bar.bar.bar"] = :bar
    assert_equal(:bar, @prop["bar.bar.bar"])
    assert_equal(:bar, @prop[["bar", "bar", "bar"]])
    assert_equal(:bar, @prop[[:bar, "bar", :bar]])
  end

  def test_to_key_and_deref
    @prop["foo.foo"] = :foo
    assert_equal(:foo, @prop["fOo.FoO"])
    assert_equal(:foo, @prop[[:fOO, :FOO]])
    assert_equal(:foo, @prop[["FoO", :Foo]])
    # deref_key negative test
    assert_raises(ArgumentError) do
      @prop["baz"] = 1
      @prop["baz.qux"] = 2
    end
  end

  def test_hook_name
    tag = Object.new
    tested = false
    @prop.add_hook("foo.bar") do |key, value|
      assert_raise(FrozenError) do
	key << "baz"
      end
      tested = true
    end
    @prop["foo.bar"] = tag
    assert(tested)
  end

  def test_value_hook
    tag = Object.new
    tested = false
    @prop.add_hook("FOO.BAR.BAZ") do |key, value|
      assert_equal(["Foo", "baR", "baZ"], key)
      assert_equal(tag, value)
      tested = true
    end
    @prop["Foo.baR.baZ"] = tag
    assert_equal(tag, @prop["foo.bar.baz"])
    assert(tested)
    @prop["foo.bar"] = 1	# unhook the above block
    assert_equal(1, @prop["foo.bar"])
  end

  def test_key_hook_no_cascade
    tag = Object.new
    tested = 0
    @prop.add_hook do |key, value|
      assert(false)
    end
    @prop.add_hook(false) do |key, value|
      assert(false)
    end
    @prop.add_hook("foo") do |key, value|
      assert(false)
    end
    @prop.add_hook("foo.bar", false) do |key, value|
      assert(false)
    end
    @prop.add_hook("foo.bar.baz") do |key, value|
      assert(false)
    end
    @prop.add_hook("foo.bar.baz.qux", false) do |key, value|
      assert_equal(["foo", "bar", "baz", "qux"], key)
      assert_equal(tag, value)
      tested += 1
    end
    @prop["foo.bar.baz.qux"] = tag
    assert_equal(tag, @prop["foo.bar.baz.qux"])
    assert_equal(1, tested)
  end

  def test_key_hook_cascade
    tag = Object.new
    tested = 0
    @prop.add_hook(true) do |key, value|
      assert_equal(["foo", "bar", "baz", "qux"], key)
      assert_equal(tag, value)
      tested += 1
    end
    @prop.add_hook("foo", true) do |key, value|
      assert_equal(["foo", "bar", "baz", "qux"], key)
      assert_equal(tag, value)
      tested += 1
    end
    @prop.add_hook("foo.bar", true) do |key, value|
      assert_equal(["foo", "bar", "baz", "qux"], key)
      assert_equal(tag, value)
      tested += 1
    end
    @prop.add_hook("foo.bar.baz", true) do |key, value|
      assert_equal(["foo", "bar", "baz", "qux"], key)
      assert_equal(tag, value)
      tested += 1
    end
    @prop.add_hook("foo.bar.baz.qux", true) do |key, value|
      assert_equal(["foo", "bar", "baz", "qux"], key)
      assert_equal(tag, value)
      tested += 1
    end
    @prop["foo.bar.baz.qux"] = tag
    assert_equal(tag, @prop["foo.bar.baz.qux"])
    assert_equal(5, tested)
  end

  def test_keys
    assert(@prop.keys.empty?)
    @prop["foo"] = 1
    @prop["bar"]
    @prop["BAz"] = 2
    assert_equal(2, @prop.keys.size)
    assert(@prop.keys.member?("foo"))
    assert(@prop.keys.member?("baz"))
    #
    assert_nil(@prop["a"])
    @prop["a.a"] = 1
    assert_instance_of(::SOAP::Property, @prop["a"])
    @prop["a.b"] = 1
    @prop["a.c"] = 1
    assert_equal(3, @prop["a"].keys.size)
    assert(@prop["a"].keys.member?("a"))
    assert(@prop["a"].keys.member?("b"))
    assert(@prop["a"].keys.member?("c"))
  end

  def test_lshift
    assert(@prop.empty?)
    @prop << 1
    assert_equal([1], @prop.values)
    assert_equal(1, @prop["0"])
    @prop << 1
    assert_equal([1, 1], @prop.values)
    assert_equal(1, @prop["1"])
    @prop << 1
    assert_equal([1, 1, 1], @prop.values)
    assert_equal(1, @prop["2"])
    #
    @prop["abc.def"] = o = SOAP::Property.new
    tested = 0
    o.add_hook do |k, v|
      tested += 1
    end
    @prop["abc.def"] << 1
    @prop["abc.def"] << 2
    @prop["abc.def"] << 3
    @prop["abc.def"] << 4
    assert_equal(4, tested)
  end

  def test_lock_each
    @prop["a.b.c.d.e"] = 1
    @prop["a.b.d"] = branch = ::SOAP::Property.new
    @prop["a.b.d.e.f"] = 2
    @prop.lock
    assert(@prop.locked?)
    assert_instance_of(::SOAP::Property, @prop["a"])
    assert_raises(FrozenError) do
      @prop["b"]
    end
    #
    @prop["a"].lock
    assert_raises(FrozenError) do
      @prop["a"]
    end
    assert_instance_of(::SOAP::Property, @prop["a.b"])
    #
    @prop["a.b"].lock
    assert_raises(FrozenError) do
      @prop["a.b"]
    end
    assert_raises(FrozenError) do
      @prop["a"]
    end
    #
    @prop["a.b.c.d"].lock
    assert_instance_of(::SOAP::Property, @prop["a.b.c"])
    assert_raises(FrozenError) do
      @prop["a.b.c.d"]
    end
    assert_instance_of(::SOAP::Property, @prop["a.b.d"])
    #
    branch["e"].lock
    assert_instance_of(::SOAP::Property, @prop["a.b.d"])
    assert_raises(FrozenError) do
      @prop["a.b.d.e"]
    end
    assert_raises(FrozenError) do
      branch["e"]
    end
  end

  def test_lock_cascade
    @prop["a.a"] = nil
    @prop["a.b.c"] = 1
    @prop["b"] = false
    @prop.lock(true)
    assert(@prop.locked?)
    assert_equal(nil, @prop["a.a"])
    assert_equal(1, @prop["a.b.c"])
    assert_equal(false, @prop["b"])
    assert_raises(FrozenError) do
      @prop["c"]
    end
    assert_raises(FrozenError) do
      @prop["c"] = 2
    end
    assert_raises(FrozenError) do
      @prop["a.b.R"]
    end
    assert_raises(FrozenError) do
      @prop.add_hook do
	assert(false)
      end
    end
    assert_raises(FrozenError) do
      @prop.add_hook("c") do
	assert(false)
      end
    end
    assert_raises(FrozenError) do
      @prop.add_hook("a.c") do
	assert(false)
      end
    end
    assert_nil(@prop["a.a"])
    @prop["a.a"] = 2
    assert_equal(2, @prop["a.a"])
    #
    @prop.unlock(true)
    assert_nil(@prop["c"])
    @prop["c"] = 2
    assert_equal(2, @prop["c"])
    @prop["a.d.a.a"] = :foo
    assert_equal(:foo, @prop["a.d.a.a"])
    tested = false
    @prop.add_hook("a.c") do |name, value|
      assert(true)
      tested = true
    end
    @prop["a.c"] = 3
    assert(tested)
  end

  def test_hook_then_lock
    tested = false
    @prop.add_hook("a.b.c") do |name, value|
      assert_equal(["a", "b", "c"], name)
      tested = true
    end
    @prop["a.b"].lock
    assert(!tested)
    @prop["a.b.c"] = 5
    assert(tested)
    assert_equal(5, @prop["a.b.c"])
    assert_raises(FrozenError) do
      @prop["a.b.d"] = 5
    end
  end

  def test_lock_unlock_return
    assert_equal(@prop, @prop.lock)
    assert_equal(@prop, @prop.unlock)
  end

  def test_lock_split
    @prop["a.b.c"] = 1
    assert_instance_of(::SOAP::Property, @prop["a.b"])
    @prop["a.b.d"] = branch = ::SOAP::Property.new
    @prop["a.b.d.e"] = 2
    assert_equal(branch, @prop["a.b.d"])
    assert_equal(branch, @prop[:a][:b][:d])
    @prop.lock(true)
    # split error 1
    assert_raises(FrozenError) do
      @prop["a.b"]
    end
    # split error 2
    assert_raises(FrozenError) do
      @prop["a"]
    end
    @prop["a.b.c"] = 2
    assert_equal(2, @prop["a.b.c"])
    # replace error
    assert_raises(FrozenError) do
      @prop["a.b.c"] = ::SOAP::Property.new
    end
    # override error
    assert_raises(FrozenError) do
      @prop["a.b"] = 1
    end
    #
    assert_raises(FrozenError) do
      @prop["a.b.d"] << 1
    end
    assert_raises(FrozenError) do
      branch << 1
    end
    branch.unlock(true)
    branch << 1
    branch << 2
    branch << 3
    assert_equal(2, @prop["a.b.d.e"])
    assert_equal(1, @prop["a.b.d.1"])
    assert_equal(2, @prop["a.b.d.2"])
    assert_equal(3, @prop["a.b.d.3"])
  end
end


end
