require_relative '../../spec_helper'

describe "String#unpack1" do
  it "returns the first value of #unpack" do
    "ABCD".unpack1('x3C').should == "ABCD".unpack('x3C')[0]
    "\u{3042 3044 3046}".unpack1("U*").should == 0x3042
    "aG9nZWZ1Z2E=".unpack1("m").should == "hogefuga"
    "A".unpack1("B*").should == "01000001"
  end
end
