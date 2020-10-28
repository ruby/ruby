# frozen_string_literal: false
require 'test/unit'
require '-test-/marshal/internal_ivar'

module Bug end

module Bug::Marshal
  class TestInternalIVar < Test::Unit::TestCase
    def test_marshal
      v = InternalIVar.new("hello", "world", "bye")
      assert_equal("hello", v.normal)
      assert_equal("world", v.internal)
      assert_equal("bye", v.encoding_short)
      dump = assert_warn(/instance variable `E' on class \S+ is not dumped/) {
        ::Marshal.dump(v)
      }
      v = assert_nothing_raised {break ::Marshal.load(dump)}
      assert_instance_of(InternalIVar, v)
      assert_equal("hello", v.normal)
      assert_nil(v.internal)
      assert_nil(v.encoding_short)
    end
  end
end
