require 'test/unit'
require 'ostruct'

class TC_OpenStruct < Test::Unit::TestCase
  def test_equality
    o1 = OpenStruct.new
    o2 = OpenStruct.new
    assert_equal(o1, o2)

    o1.a = 'a'
    assert_not_equal(o1, o2)

    o2.a = 'a'
    assert_equal(o1, o2)

    o1.a = 'b'
    assert_not_equal(o1, o2)

    o2 = Object.new
    o2.instance_eval{@table = {:a => 'b'}}
    assert_not_equal(o1, o2)
  end
end
