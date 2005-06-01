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

  # [ruby-dev:26247] more than 10 struct members causes segmentation fault
  def test_morethan10members
    list = %w( a b c d  e f g h  i j k l  m n o p )
    until list.empty?
      c = Struct.new(* list.map {|ch| ch.intern }).new
      list.each do |ch|
        c.__send__(ch)
      end
      list.pop
    end
  end
end
