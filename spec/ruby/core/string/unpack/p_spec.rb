require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/basic'
require_relative 'shared/taint'

describe "String#unpack with format 'P'" do
  it_behaves_like :string_unpack_basic, 'P'
  it_behaves_like :string_unpack_taint, 'P'

  it "round-trips a string through pack and unpack" do
    ["hello"].pack("P").unpack("P5").should == ["hello"]
  end

  it "cannot unpack a string except from the same object that created it, or a duplicate of it" do
    packed = ["hello"].pack("P")
    packed.unpack("P5").should == ["hello"]
    packed.dup.unpack("P5").should == ["hello"]
    -> { packed.to_sym.to_s.unpack("P5") }.should raise_error(ArgumentError, /no associated pointer/)
  end

  it "taints the unpacked string" do
    ["hello"].pack("P").unpack("P5").first.tainted?.should be_true
  end

  it "reads as many characters as specified" do
    ["hello"].pack("P").unpack("P1").should == ["h"]
  end

  it "reads only as far as a NUL character" do
    ["hello"].pack("P").unpack("P10").should == ["hello"]
  end
end

describe "String#unpack with format 'p'" do
  it_behaves_like :string_unpack_basic, 'p'
  it_behaves_like :string_unpack_taint, 'p'

  it "round-trips a string through pack and unpack" do
    ["hello"].pack("p").unpack("p").should == ["hello"]
  end

  it "cannot unpack a string except from the same object that created it, or a duplicate of it" do
    packed = ["hello"].pack("p")
    packed.unpack("p").should == ["hello"]
    packed.dup.unpack("p").should == ["hello"]
    -> { packed.to_sym.to_s.unpack("p") }.should raise_error(ArgumentError, /no associated pointer/)
  end

  it "taints the unpacked string" do
    ["hello"].pack("p").unpack("p").first.tainted?.should be_true
  end
end
