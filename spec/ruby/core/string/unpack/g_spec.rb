require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/float'

describe "String#unpack with format 'G'" do
  it_behaves_like :string_unpack_basic, 'G'
  it_behaves_like :string_unpack_double_be, 'G'
end

describe "String#unpack with format 'g'" do
  it_behaves_like :string_unpack_basic, 'g'
  it_behaves_like :string_unpack_float_be, 'g'
end
