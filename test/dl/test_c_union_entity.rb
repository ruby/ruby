require_relative 'test_base'

require 'dl/struct'

class DL::TestCUnionEntity < DL::TestBase
  def test_class_size
    size = DL::CUnionEntity.size([DL::TYPE_DOUBLE, DL::TYPE_CHAR])

    assert_equal DL::SIZEOF_DOUBLE, size
  end

  def test_class_size_with_count
    size = DL::CUnionEntity.size([[DL::TYPE_DOUBLE, 2], [DL::TYPE_CHAR, 20]])

    assert_equal DL::SIZEOF_CHAR * 20, size
  end

  def test_set_ctypes
    union = DL::CUnionEntity.malloc [DL::TYPE_INT, DL::TYPE_LONG]
    union.assign_names %w[int long]

    # this test is roundabout because the stored ctypes are not accessible
    union['long'] = 1
    assert_equal 1, union['long']

    union['int'] = 1
    assert_equal 1, union['int']
  end
end

