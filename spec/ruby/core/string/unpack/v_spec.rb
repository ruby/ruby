require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/integer'

describe "String#unpack with format 'V'" do
  it_behaves_like :string_unpack_basic, 'V'
  it_behaves_like :string_unpack_32bit_le, 'V'
  it_behaves_like :string_unpack_32bit_le_unsigned, 'V'
  it_behaves_like :string_unpack_no_platform, 'V'
end

describe "String#unpack with format 'v'" do
  it_behaves_like :string_unpack_basic, 'v'
  it_behaves_like :string_unpack_16bit_le, 'v'
  it_behaves_like :string_unpack_16bit_le_unsigned, 'v'
  it_behaves_like :string_unpack_no_platform, 'v'
end
