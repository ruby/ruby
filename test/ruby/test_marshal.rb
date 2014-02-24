require 'test/unit'
require 'tempfile'
require_relative 'marshaltestlib'

class TestMarshal < Test::Unit::TestCase
  include MarshalTestLib

  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def encode(o)
    Marshal.dump(o)
  end

  def decode(s)
    Marshal.load(s)
  end

  def fact(n)
    return 1 if n == 0
    f = 1
    while n>0
      f *= n
      n -= 1
    end
    return f
  end

  def test_marshal
    a = [1, 2, 3, [4,5,"foo"], {1=>"bar"}, 2.5, fact(30)]
    assert_equal a, Marshal.load(Marshal.dump(a))

    [[1,2,3,4], [81, 2, 118, 3146]].each { |w,x,y,z|
      obj = (x.to_f + y.to_f / z.to_f) * Math.exp(w.to_f / (x.to_f + y.to_f / z.to_f))
      assert_equal obj, Marshal.load(Marshal.dump(obj))
    }

    bug3659 = '[ruby-dev:41936]'
    [1.0, 10.0, 100.0, 110.0].each {|x|
      assert_equal(x, Marshal.load(Marshal.dump(x)), bug3659)
    }
  end

  StrClone = String.clone
  def test_marshal_cloned_class
    assert_instance_of(StrClone, Marshal.load(Marshal.dump(StrClone.new("abc"))))
  end

  def test_inconsistent_struct
    TestMarshal.const_set :StructOrNot, Struct.new(:a)
    s = Marshal.dump(StructOrNot.new(1))
    TestMarshal.instance_eval { remove_const :StructOrNot }
    TestMarshal.const_set :StructOrNot, Class.new
    assert_raise(TypeError, "[ruby-dev:31709]") { Marshal.load(s) }
  end

  def test_struct_invalid_members
    TestMarshal.const_set :StructInvalidMembers, Struct.new(:a)
    assert_raise(TypeError, "[ruby-dev:31759]") {
      Marshal.load("\004\bIc&TestMarshal::StructInvalidMembers\006:\020__members__\"\bfoo")
      TestMarshal::StructInvalidMembers.members
    }
  end

  class C
    def initialize(str)
      @str = str
    end
    attr_reader :str
    def _dump(limit)
      @str
    end
    def self._load(s)
      new(s)
    end
  end

  def test_too_long_string
    data = Marshal.dump(C.new("a".force_encoding("ascii-8bit")))
    data[-2, 1] = "\003\377\377\377"
    assert_raise_with_message(ArgumentError, "marshal data too short", "[ruby-dev:32054]") {
      Marshal.load(data)
    }
  end


  def test_userdef_encoding
    s1 = "\xa4\xa4".force_encoding("euc-jp")
    o1 = C.new(s1)
    m = Marshal.dump(o1)
    o2 = Marshal.load(m)
    s2 = o2.str
    assert_equal(s1, s2)
  end

  def test_pipe
    o1 = C.new("a" * 10000)

    o2 = IO.pipe do |r, w|
      Thread.new {Marshal.dump(o1, w)}
      Marshal.load(r)
    end
    assert_equal(o1.str, o2.str)

    o2 = IO.pipe do |r, w|
      Thread.new {Marshal.dump(o1, w, 2)}
      Marshal.load(r)
    end
    assert_equal(o1.str, o2.str)

    assert_raise(TypeError) { Marshal.dump("foo", Object.new) }
    assert_raise(TypeError) { Marshal.load(Object.new) }
  end

  def test_limit
    assert_equal([[[]]], Marshal.load(Marshal.dump([[[]]], 3)))
    assert_raise(ArgumentError) { Marshal.dump([[[]]], 2) }
    assert_nothing_raised(ArgumentError, '[ruby-core:24100]') { Marshal.dump("\u3042", 1) }
  end

  def test_userdef_invalid
    o = C.new(nil)
    assert_raise(TypeError) { Marshal.dump(o) }
  end

  def test_class
    o = class << Object.new; self; end
    assert_raise(TypeError) { Marshal.dump(o) }
    assert_equal(Object, Marshal.load(Marshal.dump(Object)))
    assert_equal(Enumerable, Marshal.load(Marshal.dump(Enumerable)))
  end

  class C2
    def initialize(ary)
      @ary = ary
    end
    def _dump(s)
      @ary.clear
      "foo"
    end
  end

  def test_modify_array_during_dump
    a = []
    o = C2.new(a)
    a << o << nil
    assert_raise(RuntimeError) { Marshal.dump(a) }
  end

  def test_change_class_name
    eval("class C3; def _dump(s); 'foo'; end; end")
    m = Marshal.dump(C3.new)
    assert_raise(TypeError) { Marshal.load(m) }
    eval("C3 = nil")
    assert_raise(TypeError) { Marshal.load(m) }
  end

  def test_change_struct
    eval("C3 = Struct.new(:foo, :bar)")
    m = Marshal.dump(C3.new("FOO", "BAR"))
    eval("C3 = Struct.new(:foo)")
    assert_raise(TypeError) { Marshal.load(m) }
    eval("C3 = Struct.new(:foo, :baz)")
    assert_raise(TypeError) { Marshal.load(m) }
  end

  class C4
    def initialize(gc)
      @gc = gc
    end
    def _dump(s)
      GC.start if @gc
      "foo"
    end
  end

  def test_gc
    assert_nothing_raised do
      Marshal.dump((0..1000).map {|x| C4.new(x % 50 == 25) })
    end
  end

  def test_taint
    x = Object.new
    x.taint
    s = Marshal.dump(x)
    assert_equal(true, s.tainted?)
    y = Marshal.load(s)
    assert_equal(true, y.tainted?)
  end

  def test_taint_each_object
    x = Object.new
    obj = [[x]]

    # clean object causes crean stream
    assert_equal(false, obj.tainted?)
    assert_equal(false, obj.first.tainted?)
    assert_equal(false, obj.first.first.tainted?)
    s = Marshal.dump(obj)
    assert_equal(false, s.tainted?)

    # tainted object causes tainted stream
    x.taint
    assert_equal(false, obj.tainted?)
    assert_equal(false, obj.first.tainted?)
    assert_equal(true, obj.first.first.tainted?)
    t = Marshal.dump(obj)
    assert_equal(true, t.tainted?)

    # clean stream causes clean objects
    assert_equal(false, s.tainted?)
    y = Marshal.load(s)
    assert_equal(false, y.tainted?)
    assert_equal(false, y.first.tainted?)
    assert_equal(false, y.first.first.tainted?)

    # tainted stream causes tainted objects
    assert_equal(true, t.tainted?)
    y = Marshal.load(t)
    assert_equal(true, y.tainted?)
    assert_equal(true, y.first.tainted?)
    assert_equal(true, y.first.first.tainted?)

    # same tests by different senario
    s.taint
    assert_equal(true, s.tainted?)
    y = Marshal.load(s)
    assert_equal(true, y.tainted?)
    assert_equal(true, y.first.tainted?)
    assert_equal(true, y.first.first.tainted?)
  end

  def test_symbol2
    [:ruby, :"\u{7d05}\u{7389}"].each do |sym|
      assert_equal(sym, Marshal.load(Marshal.dump(sym)), '[ruby-core:24788]')
    end
    bug2548 = '[ruby-core:27375]'
    ary = [:$1, nil]
    assert_equal(ary, Marshal.load(Marshal.dump(ary)), bug2548)
  end

  ClassUTF8 = eval("class R\u{e9}sum\u{e9}; self; end")

  iso_8859_1 = Encoding::ISO_8859_1

  structISO8859_1 = Struct.new("r\xe9sum\xe9".force_encoding(iso_8859_1).intern)
  const_set("R\xe9sum\xe9".force_encoding(iso_8859_1), structISO8859_1)
  structISO8859_1.name
  StructISO8859_1 = structISO8859_1
  classISO8859_1 = Class.new do
    attr_accessor "r\xe9sum\xe9".force_encoding(iso_8859_1)
    eval("def initialize(x) @r\xe9sum\xe9 = x; end".force_encoding(iso_8859_1))
  end
  const_set("R\xe9sum\xe92".force_encoding(iso_8859_1), classISO8859_1)
  classISO8859_1.name
  ClassISO8859_1 = classISO8859_1

  def test_class_nonascii
    a = ClassUTF8.new
    assert_instance_of(ClassUTF8, Marshal.load(Marshal.dump(a)), '[ruby-core:24790]')

    bug1932 = '[ruby-core:24882]'

    a = StructISO8859_1.new(10)
    assert_nothing_raised(bug1932) do
      assert_equal(a, Marshal.load(Marshal.dump(a)), bug1932)
    end
    a.__send__("#{StructISO8859_1.members[0]}=", a)
    assert_nothing_raised(bug1932) do
      assert_equal(a, Marshal.load(Marshal.dump(a)), bug1932)
    end

    a = ClassISO8859_1.new(10)
    assert_nothing_raised(bug1932) do
      b = Marshal.load(Marshal.dump(a))
      assert_equal(ClassISO8859_1, b.class, bug1932)
      assert_equal(a.instance_variables, b.instance_variables, bug1932)
      a.instance_variables.each do |i|
        assert_equal(a.instance_variable_get(i), b.instance_variable_get(i), bug1932)
      end
    end
    a.__send__(a.methods(true).grep(/=\z/)[0], a)
    assert_nothing_raised(bug1932) do
      b = Marshal.load(Marshal.dump(a))
      assert_equal(ClassISO8859_1, b.class, bug1932)
      assert_equal(a.instance_variables, b.instance_variables, bug1932)
      assert_equal(b, b.instance_variable_get(a.instance_variables[0]), bug1932)
    end
  end

  def test_regexp2
    assert_equal(/\\u/, Marshal.load("\004\b/\b\\\\u\000"))
    assert_equal(/u/, Marshal.load("\004\b/\a\\u\000"))
    assert_equal(/u/, Marshal.load("\004\bI/\a\\u\000\006:\016@encoding\"\vEUC-JP"))

    bug2109 = '[ruby-core:25625]'
    a = "\x82\xa0".force_encoding(Encoding::Windows_31J)
    b = "\x82\xa2".force_encoding(Encoding::Windows_31J)
    c = [/#{a}/, /#{b}/]
    assert_equal(c, Marshal.load(Marshal.dump(c)), bug2109)

    assert_nothing_raised(ArgumentError, '[ruby-dev:40386]') do
      re = Tempfile.create("marshal_regexp") do |f|
        f.binmode.write("\x04\bI/\x00\x00\x06:\rencoding\"\rUS-ASCII")
        f.rewind
        re2 = Marshal.load(f)
        re2
      end
      assert_equal(//, re)
    end
  end

  class DumpTest
    def marshal_dump
      @@block.call(:marshal_dump)
    end

    def dump_each(&block)
      @@block = block
      Marshal.dump(self)
    end
  end

  class LoadTest
    def marshal_dump
      nil
    end
    def marshal_load(obj)
      @@block.call(:marshal_load)
    end
    def self.load_each(m, &block)
      @@block = block
      Marshal.load(m)
    end
  end

  def test_context_switch
    o = DumpTest.new
    e = o.enum_for(:dump_each)
    assert_equal(:marshal_dump, e.next)
    GC.start
    assert(true, '[ruby-dev:39425]')
    assert_raise(StopIteration) {e.next}

    o = LoadTest.new
    m = Marshal.dump(o)
    e = LoadTest.enum_for(:load_each, m)
    assert_equal(:marshal_load, e.next)
    GC.start
    assert(true, '[ruby-dev:39425]')
    assert_raise(StopIteration) {e.next}
  end

  def test_dump_buffer
    bug2390 = '[ruby-dev:39744]'
    w = ""
    def w.write(str)
      self << str.to_s
    end
    Marshal.dump(Object.new, w)
    assert_not_empty(w, bug2390)
  end

  class C5
    def marshal_dump
      "foo"
    end
    def marshal_load(foo)
      @foo = foo
    end
    def initialize(x)
      @x = x
    end
  end
  def test_marshal_dump
    c = C5.new("bar")
    s = Marshal.dump(c)
    d = Marshal.load(s)
    assert_equal("foo", d.instance_variable_get(:@foo))
    assert_equal(false, d.instance_variable_defined?(:@x))
  end

  class C6
    def initialize
      @stdin = STDIN
    end
    attr_reader :stdin
    def marshal_dump
      1
    end
    def marshal_load(x)
      @stdin = STDIN
    end
  end
  def test_marshal_dump_extra_iv
    o = C6.new
    m = nil
    assert_nothing_raised("[ruby-dev:21475] [ruby-dev:39845]") {
      m = Marshal.dump(o)
    }
    o2 = Marshal.load(m)
    assert_equal(STDIN, o2.stdin)
  end

  def test_marshal_string_encoding
    o1 = ["foo".force_encoding("EUC-JP")] + [ "bar" ] * 2
    m = Marshal.dump(o1)
    o2 = Marshal.load(m)
    assert_equal(o1, o2, "[ruby-dev:40388]")
  end

  def test_marshal_regexp_encoding
    o1 = [Regexp.new("r1".force_encoding("EUC-JP"))] + ["r2"] * 2
    m = Marshal.dump(o1)
    o2 = Marshal.load(m)
    assert_equal(o1, o2, "[ruby-dev:40416]")
  end

  def test_marshal_encoding_encoding
    o1 = [Encoding.find("EUC-JP")] + ["r2"] * 2
    m = Marshal.dump(o1)
    o2 = Marshal.load(m)
    assert_equal(o1, o2)
  end

  def test_marshal_symbol_ascii8bit
    bug6209 = '[ruby-core:43762]'
    o1 = "\xff".force_encoding("ASCII-8BIT").intern
    m = Marshal.dump(o1)
    o2 = nil
    assert_nothing_raised(EncodingError, bug6209) {o2 = Marshal.load(m)}
    assert_equal(o1, o2, bug6209)
  end

  class PrivateClass
    def initialize(foo)
      @foo = foo
    end
    attr_reader :foo
  end
  private_constant :PrivateClass

  def test_marshal_private_class
    o1 = PrivateClass.new("test")
    o2 = Marshal.load(Marshal.dump(o1))
    assert_equal(o1.class, o2.class)
    assert_equal(o1.foo, o2.foo)
  end

  def test_marshal_complex
    assert_raise(ArgumentError){Marshal.load("\x04\bU:\fComplex[\x05")}
    assert_raise(ArgumentError){Marshal.load("\x04\bU:\fComplex[\x06i\x00")}
    assert_equal(Complex(1, 2), Marshal.load("\x04\bU:\fComplex[\ai\x06i\a"))
    assert_raise(ArgumentError){Marshal.load("\x04\bU:\fComplex[\bi\x00i\x00i\x00")}
  end

  def test_marshal_rational
    assert_raise(ArgumentError){Marshal.load("\x04\bU:\rRational[\x05")}
    assert_raise(ArgumentError){Marshal.load("\x04\bU:\rRational[\x06i\x00")}
    assert_equal(Rational(1, 2), Marshal.load("\x04\bU:\rRational[\ai\x06i\a"))
    assert_raise(ArgumentError){Marshal.load("\x04\bU:\rRational[\bi\x00i\x00i\x00")}
  end

  def test_marshal_flonum_reference
    bug7348 = '[ruby-core:49323]'
    e = []
    ary = [ [2.0, e], [e] ]
    assert_equal(ary, Marshal.load(Marshal.dump(ary)), bug7348)
  end

  class TestClass
  end

  module TestModule
  end

  def test_marshal_load_should_not_taint_classes
    bug7325 = '[ruby-core:49198]'
    for c in [TestClass, TestModule]
      assert_not_predicate(c, :tainted?)
      c2 = Marshal.load(Marshal.dump(c).taint)
      assert_same(c, c2)
      assert_not_predicate(c, :tainted?, bug7325)
    end
  end

  class Bug7627 < Struct.new(:bar)
    attr_accessor :foo

    def marshal_dump; 'dump'; end  # fake dump data
    def marshal_load(*); end       # do nothing
  end

  def test_marshal_dump_struct_ivar
    bug7627 = '[ruby-core:51163]'
    obj = Bug7627.new
    obj.foo = '[Bug #7627]'

    dump   = Marshal.dump(obj)
    loaded = Marshal.load(dump)

    assert_equal(obj, loaded, bug7627)
    assert_nil(loaded.foo, bug7627)
  end

  class LoadData
    attr_reader :data
    def initialize(data)
      @data = data
    end
    alias marshal_dump data
    alias marshal_load initialize
  end

  class Bug8276 < LoadData
    def initialize(*)
      super
      freeze
    end
    alias marshal_load initialize
  end

  class FrozenData < LoadData
    def marshal_load(data)
      super
      data.instance_variables.each do |iv|
        instance_variable_set(iv, data.instance_variable_get(iv))
      end
      freeze
    end
  end

  def test_marshal_dump_excess_encoding
    bug8276 = '[ruby-core:54334] [Bug #8276]'
    t = Bug8276.new(bug8276)
    s = Marshal.dump(t)
    assert_nothing_raised(RuntimeError, bug8276) {s = Marshal.load(s)}
    assert_equal(t.data, s.data, bug8276)
  end

  def test_marshal_dump_ivar
    s = "data with ivar"
    s.instance_variable_set(:@t, 42)
    t = Bug8276.new(s)
    s = Marshal.dump(t)
    assert_raise(RuntimeError) {Marshal.load(s)}
  end

  def test_marshal_load_ivar
    s = "data with ivar"
    s.instance_variable_set(:@t, 42)
    hook = ->(v) {
      if LoadData === v
        assert_send([v, :instance_variable_defined?, :@t], v.class.name)
        assert_equal(42, v.instance_variable_get(:@t), v.class.name)
      end
      v
    }
    [LoadData, FrozenData].each do |klass|
      t = klass.new(s)
      d = Marshal.dump(t)
      v = assert_nothing_raised(RuntimeError) {break Marshal.load(d, hook)}
      assert_send([v, :instance_variable_defined?, :@t], klass.name)
      assert_equal(42, v.instance_variable_get(:@t), klass.name)
    end
  end

  def test_class_ivar
    assert_raise(TypeError) {Marshal.load("\x04\x08Ic\x1bTestMarshal::TestClass\x06:\x0e@ivar_bug\"\x08bug")}
    assert_raise(TypeError) {Marshal.load("\x04\x08IM\x1bTestMarshal::TestClass\x06:\x0e@ivar_bug\"\x08bug")}
    assert_not_operator(TestClass, :instance_variable_defined?, :@bug)
  end

  def test_module_ivar
    assert_raise(TypeError) {Marshal.load("\x04\x08Im\x1cTestMarshal::TestModule\x06:\x0e@ivar_bug\"\x08bug")}
    assert_raise(TypeError) {Marshal.load("\x04\x08IM\x1cTestMarshal::TestModule\x06:\x0e@ivar_bug\"\x08bug")}
    assert_not_operator(TestModule, :instance_variable_defined?, :@bug)
  end

  class TestForRespondToFalse
    def respond_to?(a)
      false
    end
  end

  def test_marshal_respond_to_arity
    assert_nothing_raised(ArgumentError, '[Bug #7722]') do
      Marshal.dump(TestForRespondToFalse.new)
    end
  end

  def test_packed_string
    packed = ["foo"].pack("p")
    bare = "".force_encoding(Encoding::ASCII_8BIT) << packed
    assert_equal(Marshal.dump(bare), Marshal.dump(packed))
  end

  def test_untainted_numeric
    bug8945 = '[ruby-core:57346] [Bug #8945] Numerics never be tainted'
    b = 1 << 32
    b *= b until Bignum === b
    tainted = [0, 1.0, 1.72723e-77, b].select do |x|
      Marshal.load(Marshal.dump(x).taint).tainted?
    end
    assert_empty(tainted.map {|x| [x, x.class]}, bug8945)
  end

  class Bug9523
    attr_reader :cc
    def marshal_dump
      callcc {|c| @cc = c }
      nil
    end
    def marshal_load(v)
    end
  end

  def test_continuation
    require "continuation"
    c = Bug9523.new
    assert_raise_with_message(RuntimeError, /Marshal\.dump reentered at marshal_dump/) do
      Marshal.dump(c)
      c.cc.call
    end
  end
end
