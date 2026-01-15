# frozen_string_literal: false
require 'test/unit'
require '-test-/marshal/internal_ivar'

module Bug end

module Bug::Marshal
  class TestInternalIVar < Test::Unit::TestCase
    def test_marshal
      v = InternalIVar.new("hello", "world", "bye", "hi")
      assert_equal("hello", v.normal)
      assert_equal("world", v.internal)
      assert_equal("bye", v.encoding_short)
      assert_equal("hi", v.encoding_long)
      warnings = ->(s) {
        w = s.scan(/instance variable '(.+?)' on class \S+ is not dumped/)
        assert_equal(%w[E K encoding], w.flatten.sort)
      }
      dump = assert_warn(warnings) {
        ::Marshal.dump(v)
      }
      v = assert_nothing_raised {break ::Marshal.load(dump)}
      assert_instance_of(InternalIVar, v)
      assert_equal("hello", v.normal)
      assert_nil(v.internal)
      assert_nil(v.encoding_short)
      assert_nil(v.encoding_long)
    end
  end
end
