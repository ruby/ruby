require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/float'

describe "String#unpack with format 'E'" do
  it_behaves_like :string_unpack_basic, 'E'
  it_behaves_like :string_unpack_double_le, 'E'
end

describe "String#unpack with format 'e'" do
  it_behaves_like :string_unpack_basic, 'e'
  it_behaves_like :string_unpack_float_le, 'e'
end
