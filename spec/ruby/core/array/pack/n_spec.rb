require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/integer'

describe "Array#pack with format 'N'" do
  it_behaves_like :array_pack_basic, 'N'
  it_behaves_like :array_pack_basic_non_float, 'N'
  it_behaves_like :array_pack_arguments, 'N'
  it_behaves_like :array_pack_numeric_basic, 'N'
  it_behaves_like :array_pack_integer, 'N'
  it_behaves_like :array_pack_no_platform, 'N'
  it_behaves_like :array_pack_32bit_be, 'N'
end

describe "Array#pack with format 'n'" do
  it_behaves_like :array_pack_basic, 'n'
  it_behaves_like :array_pack_basic_non_float, 'n'
  it_behaves_like :array_pack_arguments, 'n'
  it_behaves_like :array_pack_numeric_basic, 'n'
  it_behaves_like :array_pack_integer, 'n'
  it_behaves_like :array_pack_no_platform, 'n'
  it_behaves_like :array_pack_16bit_be, 'n'
end
