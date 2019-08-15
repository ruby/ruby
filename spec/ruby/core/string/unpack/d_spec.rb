require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/float'

little_endian do
  describe "String#unpack with format 'D'" do
    it_behaves_like :string_unpack_basic, 'D'
    it_behaves_like :string_unpack_double_le, 'D'
  end

  describe "String#unpack with format 'd'" do
    it_behaves_like :string_unpack_basic, 'd'
    it_behaves_like :string_unpack_double_le, 'd'
  end
end

big_endian do
  describe "String#unpack with format 'D'" do
    it_behaves_like :string_unpack_basic, 'D'
    it_behaves_like :string_unpack_double_be, 'D'
  end

  describe "String#unpack with format 'd'" do
    it_behaves_like :string_unpack_basic, 'd'
    it_behaves_like :string_unpack_double_be, 'd'
  end
end
