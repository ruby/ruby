require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/numeric_basic'
require_relative 'shared/float'

describe "Array#pack with format 'G'" do
  it_behaves_like :array_pack_basic, 'G'
  it_behaves_like :array_pack_basic_float, 'G'
  it_behaves_like :array_pack_arguments, 'G'
  it_behaves_like :array_pack_no_platform, 'G'
  it_behaves_like :array_pack_numeric_basic, 'G'
  it_behaves_like :array_pack_float, 'G'
  it_behaves_like :array_pack_double_be, 'G'
end

describe "Array#pack with format 'g'" do
  it_behaves_like :array_pack_basic, 'g'
  it_behaves_like :array_pack_basic_float, 'g'
  it_behaves_like :array_pack_arguments, 'g'
  it_behaves_like :array_pack_no_platform, 'g'
  it_behaves_like :array_pack_numeric_basic, 'g'
  it_behaves_like :array_pack_float, 'g'
  it_behaves_like :array_pack_float_be, 'g'
end
