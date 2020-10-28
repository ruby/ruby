require_relative '../../spec_helper'

require 'base64'

describe "Base64#encode64" do
  it "returns the Base64-encoded version of the given string" do
    Base64.encode64("Now is the time for all good coders\nto learn Ruby").should ==
      "Tm93IGlzIHRoZSB0aW1lIGZvciBhbGwgZ29vZCBjb2RlcnMKdG8gbGVhcm4g\nUnVieQ==\n"
  end

  it "returns the Base64-encoded version of the given string" do
    Base64.encode64('Send reinforcements').should == "U2VuZCByZWluZm9yY2VtZW50cw==\n"
  end

  it "returns the Base64-encoded version of the given shared string" do
    Base64.encode64("Now is the time for all good coders\nto learn Ruby".split("\n").last).should ==
      "dG8gbGVhcm4gUnVieQ==\n"
  end

  it "returns a US_ASCII encoded string" do
    Base64.encode64("HI").encoding.should == Encoding::US_ASCII
  end
end
