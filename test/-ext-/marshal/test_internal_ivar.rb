# frozen_string_literal: false
require 'test/unit'
require '-test-/marshal/internal_ivar'

module Bug end

module Bug::Marshal
  class TestInternalIVar < Test::Unit::TestCase
    def test_marshal
      v = InternalIVar.new("hello", "world")
      assert_equal("hello", v.normal)
      assert_equal("world", v.internal)
      dump = ::Marshal.dump(v)
      v = assert_nothing_raised {break ::Marshal.load(dump)}
      assert_instance_of(InternalIVar, v)
      assert_equal("hello", v.normal)
      assert_nil(v.internal)
    end
  end
end
