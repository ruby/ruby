require 'test/unit'

$KCODE = 'none'

class TestStruct < Test::Unit::TestCase
  def test_struct
    struct_test = Struct.new("Test", :foo, :bar)
    assert(struct_test == Struct::Test)
    
    test = struct_test.new(1, 2)
    assert(test.foo == 1 && test.bar == 2)
    assert(test[0] == 1 && test[1] == 2)
    
    a, b = test.to_a
    assert(a == 1 && b == 2)
    
    test[0] = 22
    assert(test.foo == 22)
    
    test.bar = 47
    assert(test.bar == 47)
  end 
end
