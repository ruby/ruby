require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/integer'

describe "Array#pack with format 'Q'" do
  it_behaves_like :array_pack_basic, 'Q'
  it_behaves_like :array_pack_basic_non_float, 'Q'
  it_behaves_like :array_pack_arguments, 'Q'
  it_behaves_like :array_pack_numeric_basic, 'Q'
  it_behaves_like :array_pack_integer, 'Q'
end

describe "Array#pack with format 'q'" do
  it_behaves_like :array_pack_basic, 'q'
  it_behaves_like :array_pack_basic_non_float, 'q'
  it_behaves_like :array_pack_arguments, 'q'
  it_behaves_like :array_pack_numeric_basic, 'q'
  it_behaves_like :array_pack_integer, 'q'
end

describe "Array#pack with format 'Q'" do
  describe "with modifier '<'" do
    it_behaves_like :array_pack_64bit_le, 'Q<'
  end

  describe "with modifier '>'" do
    it_behaves_like :array_pack_64bit_be, 'Q>'
  end
end

describe "Array#pack with format 'q'" do
  describe "with modifier '<'" do
    it_behaves_like :array_pack_64bit_le, 'q<'
  end

  describe "with modifier '>'" do
    it_behaves_like :array_pack_64bit_be, 'q>'
  end
end

little_endian do
  describe "Array#pack with format 'Q'" do
    it_behaves_like :array_pack_64bit_le, 'Q'
  end

  describe "Array#pack with format 'q'" do
    it_behaves_like :array_pack_64bit_le, 'q'
  end
end

big_endian do
  describe "Array#pack with format 'Q'" do
    it_behaves_like :array_pack_64bit_be, 'Q'
  end

  describe "Array#pack with format 'q'" do
    it_behaves_like :array_pack_64bit_be, 'q'
  end
end
