require_relative 'test_base'

require 'dl/cparser'

class DL::TestCUnionEntity < DL::TestBase
  def test_class_size
    size = DL::CUnionEntity.size([DL::TYPE_DOUBLE, DL::TYPE_CHAR])

    assert_equal DL::SIZEOF_DOUBLE, size
  end

  def test_class_size_with_count
    size = DL::CUnionEntity.size([[DL::TYPE_DOUBLE, 2], [DL::TYPE_CHAR, 20]])

    assert_equal DL::SIZEOF_CHAR * 20, size
  end
end

