require 'test/unit'
require 'marshaltestlib'

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
    TestMarshal.const_set :S, Struct.new(:a)
    s = Marshal.dump(S.new(1))
    TestMarshal.instance_eval { remove_const :S }
    TestMarshal.const_set :S, Class.new
    assert_raise(TypeError, "[ruby-dev:31709]") { Marshal.load(s) }
  end
end
