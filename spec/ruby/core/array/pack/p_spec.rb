require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'

describe "Array#pack with format 'P'" do
  it_behaves_like :array_pack_basic_non_float, 'P'
end

describe "Array#pack with format 'p'" do
  it_behaves_like :array_pack_basic_non_float, 'p'
end
