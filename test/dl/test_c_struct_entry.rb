require_relative 'test_base'

require 'dl/cparser'

class DL::TestCStructEntity < DL::TestBase
  def test_class_size
    types = [DL::TYPE_DOUBLE, DL::TYPE_CHAR]

    size = DL::CStructEntity.size types

    alignments = types.map { |type| DL::PackInfo::ALIGN_MAP[type] }

    expected = DL::PackInfo.align 0, alignments[0]
    expected += DL::PackInfo::SIZE_MAP[DL::TYPE_DOUBLE]

    expected = DL::PackInfo.align expected, alignments[1]
    expected += DL::PackInfo::SIZE_MAP[DL::TYPE_CHAR]

    expected = DL::PackInfo.align expected, alignments.max

    assert_equal expected, size
  end

  def test_class_size_with_count
    size = DL::CStructEntity.size([[DL::TYPE_DOUBLE, 2], [DL::TYPE_CHAR, 20]])

    assert_equal DL::TYPE_DOUBLE * 2 + DL::SIZEOF_CHAR * 20, size
  end
  def test_class_size_with_count
    size = DL::CStructEntity.size([[DL::TYPE_DOUBLE, 2], [DL::TYPE_CHAR, 20]])

    types = [DL::TYPE_DOUBLE, DL::TYPE_CHAR]
    alignments = types.map { |type| DL::PackInfo::ALIGN_MAP[type] }

    expected = DL::PackInfo.align 0, alignments[0]
    expected += DL::PackInfo::SIZE_MAP[DL::TYPE_DOUBLE] * 2

    expected = DL::PackInfo.align expected, alignments[1]
    expected += DL::PackInfo::SIZE_MAP[DL::TYPE_CHAR] * 20

    expected = DL::PackInfo.align expected, alignments.max

    assert_equal expected, size
  end
end

