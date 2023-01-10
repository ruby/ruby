require_relative '../../spec_helper'

describe "String#unpack" do
  it "raises a TypeError when passed nil" do
    -> { "abc".unpack(nil) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed an Integer" do
    -> { "abc".unpack(1) }.should raise_error(TypeError)
  end

  ruby_version_is "3.1" do
    it "starts unpacking from the given offset" do
      "abc".unpack("CC", offset: 1).should == [98, 99]
    end

    it "traits offset as a bytes offset" do
      "؈".unpack("CC").should == [216, 136]
      "؈".unpack("CC", offset: 1).should == [136, nil]
    end

    it "raises an ArgumentError when the offset is negative" do
      -> { "a".unpack("C", offset: -1) }.should raise_error(ArgumentError, "offset can't be negative")
    end

    it "returns nil if the offset is at the end of the string" do
      "a".unpack("C", offset: 1).should == [nil]
    end

    it "raises an ArgumentError when the offset is larget than the string" do
      -> { "a".unpack("C", offset: 2) }.should raise_error(ArgumentError, "offset outside of string")
    end
  end
end
