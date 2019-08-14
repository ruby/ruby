# frozen_string_literal: false
require 'test/unit'
require "-test-/string"

class Test_StrSetLen < Test::Unit::TestCase
  def setup
    @s0 = [*"a".."z"].join("").freeze
    @s1 = Bug::String.new(@s0)
  end

  def teardown
    orig = [*"a".."z"].join("")
    assert_equal(orig, @s0)
  end

  def test_non_shared
    @s1.modify!
    assert_equal("abc", @s1.set_len(3))
  end

  def test_shared
    assert_raise(RuntimeError) {
      assert_equal("abc", @s1.set_len(3))
    }
  end

  def test_capacity_equals_to_new_size
    bug12757 = "[ruby-core:77257] [Bug #12757]"
    # fill to ensure capacity does not decrease with force_encoding
    str = Bug::String.new("\x00" * 128, capacity: 128)
    str.force_encoding("UTF-32BE")
    assert_equal 128, Bug::String.capacity(str)
    assert_equal 127, str.set_len(127).bytesize, bug12757
  end
end
