require_relative '../../spec_helper'

require 'base64'

describe "Base64#strict_encode64" do
  it "returns the Base64-encoded version of the given string" do
    Base64.strict_encode64("Now is the time for all good coders\nto learn Ruby").should ==
      "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4gUnVieQ=="
  end

  it "returns the Base64-encoded version of the given shared string" do
    Base64.strict_encode64("Now is the time for all good coders\nto learn Ruby".split("\n").last).should ==
      "dG8gbGVhcm4gUnVieQ=="
  end

  it "returns a US_ASCII encoded string" do
    Base64.strict_encode64("HI").encoding.should == Encoding::US_ASCII
  end
end
