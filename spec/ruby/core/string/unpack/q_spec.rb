require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/integer'

describe "String#unpack with format 'Q'" do
  describe "with modifier '<'" do
    it_behaves_like :string_unpack_64bit_le, 'Q<'
    it_behaves_like :string_unpack_64bit_le_unsigned, 'Q<'
  end

  describe "with modifier '>'" do
    it_behaves_like :string_unpack_64bit_be, 'Q>'
    it_behaves_like :string_unpack_64bit_be_unsigned, 'Q>'
  end
end

describe "String#unpack with format 'q'" do
  describe "with modifier '<'" do
    it_behaves_like :string_unpack_64bit_le, 'q<'
    it_behaves_like :string_unpack_64bit_le_signed, 'q<'
  end

  describe "with modifier '>'" do
    it_behaves_like :string_unpack_64bit_be, 'q>'
    it_behaves_like :string_unpack_64bit_be_signed, 'q>'
  end
end

describe "String#unpack with format 'Q'" do
  it_behaves_like :string_unpack_basic, 'Q'
end

describe "String#unpack with format 'q'" do
  it_behaves_like :string_unpack_basic, 'q'
end

little_endian do
  describe "String#unpack with format 'Q'" do
    it_behaves_like :string_unpack_64bit_le, 'Q'
    it_behaves_like :string_unpack_64bit_le_extra, 'Q'
    it_behaves_like :string_unpack_64bit_le_unsigned, 'Q'
  end

  describe "String#unpack with format 'q'" do
    it_behaves_like :string_unpack_64bit_le, 'q'
    it_behaves_like :string_unpack_64bit_le_extra, 'q'
    it_behaves_like :string_unpack_64bit_le_signed, 'q'
  end
end

big_endian do
  describe "String#unpack with format 'Q'" do
    it_behaves_like :string_unpack_64bit_be, 'Q'
    it_behaves_like :string_unpack_64bit_be_extra, 'Q'
    it_behaves_like :string_unpack_64bit_be_unsigned, 'Q'
  end

  describe "String#unpack with format 'q'" do
    it_behaves_like :string_unpack_64bit_be, 'q'
    it_behaves_like :string_unpack_64bit_be_extra, 'q'
    it_behaves_like :string_unpack_64bit_be_signed, 'q'
  end
end
