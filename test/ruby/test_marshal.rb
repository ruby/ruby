require 'test/unit'
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
    x = [1, 2, 3, [4,5,"foo"], {1=>"bar"}, 2.5, fact(30)]
    assert_equal x, Marshal.load(Marshal.dump(x))

    [[1,2,3,4], [81, 2, 118, 3146]].each { |w,x,y,z|
      obj = (x.to_f + y.to_f / z.to_f) * Math.exp(w.to_f / (x.to_f + y.to_f / z.to_f))
      assert_equal obj, Marshal.load(Marshal.dump(obj))
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
    Marshal.load("\004\bIc&TestMarshal::StructInvalidMembers\006:\020__members__\"\bfoo")
    assert_raise(TypeError, "[ruby-dev:31759]") {
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
    e = assert_raise(ArgumentError, "[ruby-dev:32054]") {
      Marshal.load(data)
    }
    assert_equal("marshal data too short", e.message)
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

    r, w = IO.pipe
    t = Thread.new { Marshal.load(r) }
    Marshal.dump(o1, w)
    o2 = t.value
    assert_equal(o1.str, o2.str)

    r, w = IO.pipe
    t = Thread.new { Marshal.load(r) }
    Marshal.dump(o1, w, 2)
    o2 = t.value
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

  def test_taint_and_untrust
    x = Object.new
    x.taint
    x.untrust
    s = Marshal.dump(x)
    assert_equal(true, s.tainted?)
    assert_equal(true, s.untrusted?)
    y = Marshal.load(s)
    assert_equal(true, y.tainted?)
    assert_equal(true, y.untrusted?)
  end

  def test_symbol
    [:ruby, :"\u{7d05}\u{7389}"].each do |sym|
      assert_equal(sym, Marshal.load(Marshal.dump(sym)), '[ruby-core:24788]')
    end
  end
end
