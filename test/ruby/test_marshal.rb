require 'test/unit'
dir = File.dirname(File.expand_path(__FILE__))
orgpath = $:.dup
begin
  $:.push(dir)
  require 'marshaltestlib'
ensure
  $:.replace(orgpath)
end

class TestMarshal < Test::Unit::TestCase
  include MarshalTestLib

  def encode(o)
    stress, GC.stress = GC.stress, true
    Marshal.dump(o)
  ensure
    GC.stress = stress
  end

  def decode(s)
    stress, GC.stress = GC.stress, true
    Marshal.load(s)
  ensure
    GC.stress = stress
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

  StrClone=String.clone;

  def test_marshal
    $x = [1,2,3,[4,5,"foo"],{1=>"bar"},2.5,fact(30)]
    $y = Marshal.dump($x)
    assert_equal($x, Marshal.load($y))

    assert_instance_of(StrClone, Marshal.load(Marshal.dump(StrClone.new("abc"))))

    [[1,2,3,4], [81, 2, 118, 3146]].each { |w,x,y,z|
      a = (x.to_f + y.to_f / z.to_f) * Math.exp(w.to_f / (x.to_f + y.to_f / z.to_f))
      ma = Marshal.dump(a)
      b = Marshal.load(ma)
      assert_equal(a, b)
    }
  end

  class C
    def initialize(str)
      @str = str
    end
    def _dump(limit)
      @str
    end
    def self._load(s)
      new(s)
    end
  end

  def test_too_long_string
    (data = Marshal.dump(C.new("a")))[-2, 1] = "\003\377\377\377"
    e = assert_raise(ArgumentError, "[ruby-dev:32054]") {
      Marshal.load(data)
    }
    assert_equal("marshal data too short", e.message)
  end
end
