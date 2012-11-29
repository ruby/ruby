# -*- coding: us-ascii -*-
require_relative 'test_base'

EnvUtil.suppress_warning {require 'dl/struct'}

module DL
  class TestCStructEntity < TestBase
    def test_class_size
      types = [TYPE_DOUBLE, TYPE_CHAR]

      size = CStructEntity.size types

      alignments = types.map { |type| PackInfo::ALIGN_MAP[type] }

      expected = PackInfo.align 0, alignments[0]
      expected += PackInfo::SIZE_MAP[TYPE_DOUBLE]

      expected = PackInfo.align expected, alignments[1]
      expected += PackInfo::SIZE_MAP[TYPE_CHAR]

      expected = PackInfo.align expected, alignments.max

      assert_equal expected, size
    end

    def test_class_size_with_count
      size = CStructEntity.size([[TYPE_DOUBLE, 2], [TYPE_CHAR, 20]])

      types = [TYPE_DOUBLE, TYPE_CHAR]
      alignments = types.map { |type| PackInfo::ALIGN_MAP[type] }

      expected = PackInfo.align 0, alignments[0]
      expected += PackInfo::SIZE_MAP[TYPE_DOUBLE] * 2

      expected = PackInfo.align expected, alignments[1]
      expected += PackInfo::SIZE_MAP[TYPE_CHAR] * 20

      expected = PackInfo.align expected, alignments.max

      assert_equal expected, size
    end

    def test_set_ctypes
      union = CStructEntity.malloc [TYPE_INT, TYPE_LONG]
      union.assign_names %w[int long]

      # this test is roundabout because the stored ctypes are not accessible
      union['long'] = 1
      union['int'] = 2

      assert_equal 1, union['long']
      assert_equal 2, union['int']
    end
  end
end
