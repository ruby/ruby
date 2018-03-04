require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/float'

describe "Array#pack with format 'D'" do
  it_behaves_like :array_pack_basic, 'D'
  it_behaves_like :array_pack_basic_float, 'D'
  it_behaves_like :array_pack_arguments, 'D'
  it_behaves_like :array_pack_no_platform, 'D'
  it_behaves_like :array_pack_numeric_basic, 'D'
  it_behaves_like :array_pack_float, 'D'

  little_endian do
    it_behaves_like :array_pack_double_le, 'D'
  end

  big_endian do
    it_behaves_like :array_pack_double_be, 'D'
  end
end

describe "Array#pack with format 'd'" do
  it_behaves_like :array_pack_basic, 'd'
  it_behaves_like :array_pack_basic_float, 'd'
  it_behaves_like :array_pack_arguments, 'd'
  it_behaves_like :array_pack_no_platform, 'd'
  it_behaves_like :array_pack_numeric_basic, 'd'
  it_behaves_like :array_pack_float, 'd'

  little_endian do
    it_behaves_like :array_pack_double_le, 'd'
  end

  big_endian do
    it_behaves_like :array_pack_double_be, 'd'
  end
end
