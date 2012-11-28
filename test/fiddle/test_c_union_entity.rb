require_relative 'helper'

require 'fiddle/struct'

module Fiddle
  class TestCUnionEntity < TestCase
    def test_class_size
      size = CUnionEntity.size([TYPE_DOUBLE, TYPE_CHAR])

      assert_equal SIZEOF_DOUBLE, size
    end

    def test_class_size_with_count
      size = CUnionEntity.size([[TYPE_DOUBLE, 2], [TYPE_CHAR, 20]])

      assert_equal SIZEOF_CHAR * 20, size
    end

    def test_set_ctypes
      union = CUnionEntity.malloc [TYPE_INT, TYPE_LONG]
      union.assign_names %w[int long]

      # this test is roundabout because the stored ctypes are not accessible
      union['long'] = 1
      assert_equal 1, union['long']

      union['int'] = 1
      assert_equal 1, union['int']
    end
  end
end
