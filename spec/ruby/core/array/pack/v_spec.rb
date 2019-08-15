require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/integer'

describe "Array#pack with format 'V'" do
  it_behaves_like :array_pack_basic, 'V'
  it_behaves_like :array_pack_basic_non_float, 'V'
  it_behaves_like :array_pack_arguments, 'V'
  it_behaves_like :array_pack_numeric_basic, 'V'
  it_behaves_like :array_pack_integer, 'V'
  it_behaves_like :array_pack_no_platform, 'V'
  it_behaves_like :array_pack_32bit_le, 'V'
end

describe "Array#pack with format 'v'" do
  it_behaves_like :array_pack_basic, 'v'
  it_behaves_like :array_pack_basic_non_float, 'v'
  it_behaves_like :array_pack_arguments, 'v'
  it_behaves_like :array_pack_numeric_basic, 'v'
  it_behaves_like :array_pack_integer, 'v'
  it_behaves_like :array_pack_no_platform, 'v'
  it_behaves_like :array_pack_16bit_le, 'v'
end
