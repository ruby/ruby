require 'test/unit'

class TestObjectSpace < Test::Unit::TestCase
  def self.deftest_id2ref(obj)
    /:(\d+)/ =~ caller[0]
    file = $`
    line = $1.to_i
    code = <<"End"
    define_method("test_id2ref_#{line}") {\
      o = ObjectSpace._id2ref(obj.object_id);\
      assert_same(obj, o, "didn't round trip: \#{obj.inspect}");\
    }
End
    eval code, binding, file, line
  end

  deftest_id2ref(-0x4000000000000001)
  deftest_id2ref(-0x4000000000000000)
  deftest_id2ref(-0x40000001)
  deftest_id2ref(-0x40000000)
  deftest_id2ref(-1)
  deftest_id2ref(0)
  deftest_id2ref(1)
  deftest_id2ref(0x3fffffff)
  deftest_id2ref(0x40000000)
  deftest_id2ref(0x3fffffffffffffff)
  deftest_id2ref(0x4000000000000000)
  deftest_id2ref(:a)
  deftest_id2ref(:abcdefghijilkjl)
  deftest_id2ref(:==)
  deftest_id2ref(Object.new)
  deftest_id2ref(self)
  deftest_id2ref(true)
  deftest_id2ref(false)
  deftest_id2ref(nil)
end
