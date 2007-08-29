require 'test/unit'
require 'soap/marshal'


module SOAP
module Marshal


Foo1 = ::Struct.new("Foo1", :m)
Foo2 = ::Struct.new(:m)
class Foo3
  attr_accessor :m
end

class TestStruct < Test::Unit::TestCase
  def test_foo1
    org = Foo1.new
    org.m = org
    obj = convert(org)
    assert_equal(Foo1, obj.class)
    assert_equal(obj.m, obj)
  end

  def test_foo2
    org = Foo2.new
    org.m = org
    obj = convert(org)
    assert_equal(Foo2, obj.class)
    assert_equal(obj.m, obj)
  end

  def test_foo3
    org = Foo3.new
    org.m = org
    obj = convert(org)
    assert_equal(Foo3, obj.class)
    assert_equal(obj.m, obj)
  end

  def convert(obj)
    SOAP::Marshal.unmarshal(SOAP::Marshal.marshal(obj))
  end
end


end
end
