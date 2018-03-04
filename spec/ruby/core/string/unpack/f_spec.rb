require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/float'

little_endian do
  describe "String#unpack with format 'F'" do
    it_behaves_like :string_unpack_basic, 'F'
    it_behaves_like :string_unpack_float_le, 'F'
  end

  describe "String#unpack with format 'f'" do
    it_behaves_like :string_unpack_basic, 'f'
    it_behaves_like :string_unpack_float_le, 'f'
  end
end

big_endian do
  describe "String#unpack with format 'F'" do
    it_behaves_like :string_unpack_basic, 'F'
    it_behaves_like :string_unpack_float_be, 'F'
  end

  describe "String#unpack with format 'f'" do
    it_behaves_like :string_unpack_basic, 'f'
    it_behaves_like :string_unpack_float_be, 'f'
  end
end
