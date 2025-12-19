require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/integer'

ruby_version_is "4.0" do
  describe "Array#pack with format 'R'" do
    it_behaves_like :array_pack_basic, 'R'
    it_behaves_like :array_pack_basic_non_float, 'R'
    it_behaves_like :array_pack_arguments, 'R'
    it_behaves_like :array_pack_numeric_basic, 'R'
    it_behaves_like :array_pack_integer, 'R'
  end

  describe "Array#pack with format 'r'" do
    it_behaves_like :array_pack_basic, 'r'
    it_behaves_like :array_pack_basic_non_float, 'r'
    it_behaves_like :array_pack_arguments, 'r'
    it_behaves_like :array_pack_numeric_basic, 'r'
    it_behaves_like :array_pack_integer, 'r'
  end
end
