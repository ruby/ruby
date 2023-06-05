require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/taint'

describe "Array#pack with format 'P'" do
  it_behaves_like :array_pack_basic_non_float, 'P'
  it_behaves_like :array_pack_taint, 'P'

  it "produces as many bytes as there are in a pointer" do
    ["hello"].pack("P").size.should == [0].pack("J").size
  end

  it "round-trips a string through pack and unpack" do
    ["hello"].pack("P").unpack("P5").should == ["hello"]
  end

  it "with nil gives a null pointer" do
    [nil].pack("P").unpack("J").should == [0]
  end
end

describe "Array#pack with format 'p'" do
  it_behaves_like :array_pack_basic_non_float, 'p'
  it_behaves_like :array_pack_taint, 'p'

  it "produces as many bytes as there are in a pointer" do
    ["hello"].pack("p").size.should == [0].pack("J").size
  end

  it "round-trips a string through pack and unpack" do
    ["hello"].pack("p").unpack("p").should == ["hello"]
  end

  it "with nil gives a null pointer" do
    [nil].pack("p").unpack("J").should == [0]
  end
end
