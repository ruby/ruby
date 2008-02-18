require 'test/unit'
require 'require_relative'
require_relative 'marshaltestlib'

class TestMarshal < Test::Unit::TestCase
  include MarshalTestLib

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
end
