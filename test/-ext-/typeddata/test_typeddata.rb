require 'test/unit'
require "-test-/typeddata/typeddata"

class Test_TypedData < Test::Unit::TestCase
  def test_wrong_argtype
    assert_raise_with_message(TypeError, "wrong argument type false (expected typed_data)") {Bug::TypedData.check(false)}

    assert_raise_with_message(TypeError, "wrong argument type true (expected typed_data)") {Bug::TypedData.check(true)}

    assert_raise_with_message(TypeError, "wrong argument type Symbol (expected typed_data)") {Bug::TypedData.check(:e)}

    assert_raise_with_message(TypeError, "wrong argument type Fixnum (expected typed_data)") {Bug::TypedData.check(0)}

    assert_raise_with_message(TypeError, "wrong argument type String (expected typed_data)") {Bug::TypedData.check("a")}
  end
end
