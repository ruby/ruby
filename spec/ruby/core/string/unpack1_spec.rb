require_relative '../../spec_helper'

describe "String#unpack1" do
  it "returns the first value of #unpack" do
    "ABCD".unpack1('x3C').should == "ABCD".unpack('x3C')[0]
    "\u{3042 3044 3046}".unpack1("U*").should == 0x3042
    "aG9nZWZ1Z2E=".unpack1("m").should == "hogefuga"
    "A".unpack1("B*").should == "01000001"
  end

  ruby_version_is "3.1" do
    it "starts unpacking from the given offset" do
      "ZZABCD".unpack1('x3C', offset: 2).should == "ABCD".unpack('x3C')[0]
      "ZZZZaG9nZWZ1Z2E=".unpack1("m", offset: 4).should == "hogefuga"
      "ZA".unpack1("B*", offset: 1).should == "01000001"
    end

    it "raises an ArgumentError when the offset is negative" do
      -> { "a".unpack1("C", offset: -1) }.should raise_error(ArgumentError)
    end

    it "returns nil if the offset is at the end of the string" do
      "a".unpack1("C", offset: 1).should == nil
    end

    it "raises an ArgumentError when the offset is larget than the string" do
      -> { "a".unpack1("C", offset: 2) }.should raise_error(ArgumentError)
    end
  end
end
