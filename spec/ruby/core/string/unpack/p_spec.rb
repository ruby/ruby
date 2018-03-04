require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'

describe "String#unpack with format 'P'" do
  it_behaves_like :string_unpack_basic, 'P'

  it "returns a random object after consuming a size-of a machine word bytes" do
    str = "\0" * 1.size
    str.unpack("P").should be_kind_of(Object)
  end
end

describe "String#unpack with format 'p'" do
  it_behaves_like :string_unpack_basic, 'p'

  it "returns a random object after consuming a size-of a machine word bytes" do
    str = "\0" * 1.size
    str.unpack("p").should be_kind_of(Object)
  end
end
