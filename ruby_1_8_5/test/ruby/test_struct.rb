require 'test/unit'

class TestStruct < Test::Unit::TestCase
  def test_struct
    struct_test = Struct.new("Test", :foo, :bar)
    assert_equal(Struct::Test, struct_test)

    test = struct_test.new(1, 2)
    assert_equal(1, test.foo)
    assert_equal(2, test.bar)
    assert_equal(1, test[0])
    assert_equal(2, test[1])

    a, b = test.to_a
    assert_equal(1, a)
    assert_equal(2, b)

    test[0] = 22
    assert_equal(22, test.foo)

    test.bar = 47
    assert_equal(47, test.bar)
  end
end
