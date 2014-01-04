require 'test/unit'
require "-test-/string/string"

class Test_StrSetLen < Test::Unit::TestCase
  def setup
    @s0 = [*"0".."z"].join("").freeze
    @s1 = Bug::String.new(@s0)
  end

  def teardown
    orig = [*"0".."z"].join("")
    assert_equal(orig, @s0)
  end

  def test_non_shared
    @s1.modify!
    assert_equal("012", @s1.set_len(3))
  end

  def test_shared
    assert_raise(RuntimeError) {
      assert_equal("012", @s1.set_len(3))
    }
  end
end
