# frozen_string_literal: false
require 'test/unit'
require 'tempfile'
require_relative 'marshaltestlib'

class TestMarshal < Test::Unit::TestCase
  include MarshalTestLib

  def setup
    @verbose = $VERBOSE
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

    IO.pipe do |r, w|
      th = Thread.new {Marshal.dump(o1, w)}
      o2 = Marshal.load(r)
      th.join
      assert_equal(o1.str, o2.str)
    end

    IO.pipe do |r, w|
      th = Thread.new {Marshal.dump(o1, w, 2)}
      o2 = Marshal.load(r)
      th.join
      assert_equal(o1.str, o2.str)
    end

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
    self.class.__send__(:remove_const, :C3) if self.class.const_defined?(:C3)
    eval("class C3; def _dump(s); 'foo'; end; end")
    m = Marshal.dump(C3.new)
    assert_raise(TypeError) { Marshal.load(m) }
    self.class.__send__(:remove_const, :C3)
    eval("C3 = nil")
    assert_raise(TypeError) { Marshal.load(m) }
  ensure
    self.class.__send__(:remove_const, :C3) if self.class.const_defined?(:C3)
  end

  def test_change_struct
    self.class.__send__(:remove_const, :C3) if self.class.const_defined?(:C3)
    eval("C3 = Struct.new(:foo, :bar)")
    m = Marshal.dump(C3.new("FOO", "BAR"))
    self.class.__send__(:remove_const, :C3)
    eval("C3 = Struct.new(:foo)")
    assert_raise(TypeError) { Marshal.load(m) }
    self.class.__send__(:remove_const, :C3)
    eval("C3 = Struct.new(:foo, :baz)")
    assert_raise(TypeError) { Marshal.load(m) }
  ensure
    self.class.__send__(:remove_const, :C3) if self.class.const_defined?(:C3)
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

  def test_symbol2
    [:ruby, :"\u{7d05}\u{7389}"].each do |sym|
      assert_equal(sym, Marshal.load(Marshal.dump(sym)), '[ruby-core:24788]')
    end
    bug2548 = '[ruby-core:27375]'
    ary = [:$1, nil]
    assert_equal(ary, Marshal.load(Marshal.dump(ary)), bug2548)
  end

  def test_symlink
    assert_include(Marshal.dump([:a, :a]), ';')
  end

  def test_symlink_in_ivar
    bug10991 = '[ruby-core:68587] [Bug #10991]'
    sym = Marshal.load("\x04\x08" +
                       "I" ":\x0bKernel" +
                       ("\x06" +
                        ("I" ":\x07@a" +
                         ("\x06" ":\x07@b" "e;\x0""o:\x0bObject""\x0")) +
                        "0"))
    assert_equal(:Kernel, sym, bug10991)
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
    assert_raise(FrozenError) {Marshal.load(s)}
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
    def respond_to?(a, priv = false)
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
    EnvUtil.suppress_warning {require "continuation"}
    c = Bug9523.new
    assert_raise_with_message(RuntimeError, /Marshal\.dump reentered at marshal_dump/) do
      Marshal.dump(c)
      GC.start
      1000.times {"x"*1000}
      GC.start
      c.cc.call
    end
  end

  def test_undumpable_message
    c = Module.new {break module_eval("class IO\u{26a1} < IO;self;end")}
    assert_raise_with_message(TypeError, /IO\u{26a1}/) {
      Marshal.dump(c.new(0, autoclose: false))
    }
  end

  def test_undumpable_data
    c = Module.new {break module_eval("class T\u{23F0 23F3}<Time;undef _dump;self;end")}
    assert_raise_with_message(TypeError, /T\u{23F0 23F3}/) {
      Marshal.dump(c.new)
    }
  end

  def test_unloadable_data
    name = "Unloadable\u{23F0 23F3}"
    c = eval("class #{name} < Time;;self;end")
    c.class_eval {
      alias _dump_data _dump
      undef _dump
    }
    d = Marshal.dump(c.new)
    assert_raise_with_message(TypeError, /Unloadable\u{23F0 23F3}/) {
      Marshal.load(d)
    }

    # cleanup
    self.class.class_eval do
      remove_const name
    end
  end

  def test_unloadable_userdef
    name = "Userdef\u{23F0 23F3}"
    c = eval("class #{name} < Time;self;end")
    class << c
      undef _load
    end
    d = Marshal.dump(c.new)
    assert_raise_with_message(TypeError, /Userdef\u{23F0 23F3}/) {
      Marshal.load(d)
    }

    # cleanup
    self.class.class_eval do
      remove_const name
    end
  end

  def test_unloadable_usrmarshal
    c = eval("class UsrMarshal\u{23F0 23F3}<Time;self;end")
    c.class_eval {
      alias marshal_dump _dump
    }
    d = Marshal.dump(c.new)
    assert_raise_with_message(TypeError, /UsrMarshal\u{23F0 23F3}/) {
      Marshal.load(d)
    }
  end

  def test_no_internal_ids
    opt = %w[--disable=gems]
    args = [opt, 'Marshal.dump("",STDOUT)', true, true]
    kw = {encoding: Encoding::ASCII_8BIT}
    out, err, status = EnvUtil.invoke_ruby(*args, **kw)
    assert_empty(err)
    assert_predicate(status, :success?)
    expected = out

    opt << "--enable=frozen-string-literal"
    opt << "--debug=frozen-string-literal"
    out, err, status = EnvUtil.invoke_ruby(*args, **kw)
    assert_empty(err)
    assert_predicate(status, :success?)
    assert_equal(expected, out)
  end

  def test_marshal_honor_post_proc_value_for_link
    str = 'x' # for link
    obj = [str, str]
    assert_equal(['X', 'X'], Marshal.load(Marshal.dump(obj), ->(v) { v == str ? v.upcase : v }))
  end

  def test_marshal_proc_string_encoding
    string = "foo"
    payload = Marshal.dump(string)
    Marshal.load(payload, ->(v) {
      if v.is_a?(String)
        assert_equal(string, v)
        assert_equal(string.encoding, v.encoding)
      end
      v
    })
  end

  def test_marshal_proc_freeze
    object = { foo: [42, "bar"] }
    assert_equal object, Marshal.load(Marshal.dump(object), :freeze.to_proc)
  end

  def test_marshal_load_extended_class_crash
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      assert_raise_with_message(ArgumentError, /undefined/) do
        Marshal.load("\x04\be:\x0F\x00omparableo:\vObject\x00")
      end
    end;
  end

  def test_marshal_load_r_prepare_reference_crash
    crash = "\x04\bI/\x05\x00\x06:\x06E{\x06@\x05T"

    opt = %w[--disable=gems]
    assert_separately(opt, <<-RUBY)
      assert_raise_with_message(ArgumentError, /bad link/) do
        Marshal.load(#{crash.dump})
      end
    RUBY
  end

  MethodMissingWithoutRespondTo = Struct.new(:wrapped_object) do
    undef respond_to?
    def method_missing(*args, &block)
      wrapped_object.public_send(*args, &block)
    end
    def respond_to_missing?(name, private = false)
      wrapped_object.respond_to?(name, false)
    end
  end

  def test_method_missing_without_respond_to
    bug12353 = "[ruby-core:75377] [Bug #12353]: try method_missing if" \
               " respond_to? is undefined"
    obj = MethodMissingWithoutRespondTo.new("foo")
    dump = assert_nothing_raised(NoMethodError, bug12353) do
      Marshal.dump(obj)
    end
    assert_equal(obj, Marshal.load(dump))
  end

  class Bug12974
    def marshal_dump
      dup
    end
  end

  def test_marshal_dump_recursion
    assert_raise_with_message(RuntimeError, /same class instance/) do
      Marshal.dump(Bug12974.new)
    end
  end

  Bug14314 = Struct.new(:foo, keyword_init: true)

  def test_marshal_keyword_init_struct
    obj = Bug14314.new(foo: 42)
    assert_equal obj, Marshal.load(Marshal.dump(obj))
  end

  class Bug15968
    attr_accessor :bar, :baz

    def initialize
      self.bar = Bar.new(self)
    end

    class Bar
      attr_accessor :foo

      def initialize(foo)
        self.foo = foo
      end

      def marshal_dump
        if self.foo.baz
          self.foo.remove_instance_variable(:@baz)
        else
          self.foo.baz = :problem
        end
        {foo: self.foo}
      end

      def marshal_load(data)
        self.foo = data[:foo]
      end
    end
  end

  def test_marshal_dump_adding_instance_variable
    obj = Bug15968.new
    assert_raise_with_message(RuntimeError, /instance variable added/) do
      Marshal.dump(obj)
    end
  end

  def test_marshal_dump_removing_instance_variable
    obj = Bug15968.new
    obj.baz = :Bug15968
    assert_raise_with_message(RuntimeError, /instance variable removed/) do
      Marshal.dump(obj)
    end
  end

  ruby2_keywords def ruby2_keywords_hash(*a)
    a.last
  end

  def ruby2_keywords_test(key: 1)
    key
  end

  def test_marshal_with_ruby2_keywords_hash
    flagged_hash = ruby2_keywords_hash(key: 42)
    data = Marshal.dump(flagged_hash)
    hash = Marshal.load(data)
    assert_equal(42, ruby2_keywords_test(*[hash]))

    hash2 = Marshal.load(data.sub(/\x06K(?=T\z)/, "\x08KEY"))
    assert_raise(ArgumentError, /\(given 1, expected 0\)/) {
      ruby2_keywords_test(*[hash2])
    }
  end

  def test_invalid_byte_sequence_symbol
    data = Marshal.dump(:K)
    data = data.sub(/:\x06K/, "I\\&\x06:\x0dencoding\"\x0dUTF-16LE")
    assert_raise(ArgumentError, /UTF-16LE: "\\x4B"/) {
      Marshal.load(data)
    }
  end

  def exception_test
    raise
  end

  def test_marshal_exception
    begin
      exception_test
    rescue => e
      e2 = Marshal.load(Marshal.dump(e))
      assert_equal(e.message, e2.message)
      assert_equal(e.backtrace, e2.backtrace)
      assert_nil(e2.backtrace_locations) # temporal
    end
  end

  def nameerror_test
    unknown_method
  end

  def test_marshal_nameerror
    begin
      nameerror_test
    rescue NameError => e
      e2 = Marshal.load(Marshal.dump(e))
      assert_equal(e.message, e2.message)
      assert_equal(e.name, e2.name)
      assert_equal(e.backtrace, e2.backtrace)
      assert_nil(e2.backtrace_locations) # temporal
    end
  end

  class TestMarshalFreezeProc < Test::Unit::TestCase
    include MarshalTestLib

    def encode(o)
      Marshal.dump(o)
    end

    def decode(s)
      Marshal.load(s, :freeze.to_proc)
    end
  end
end
