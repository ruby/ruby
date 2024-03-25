require_relative '../../spec_helper'

require 'base64'

describe "Base64#strict_decode64" do
  it "returns the Base64-decoded version of the given string" do
    Base64.strict_decode64("U2VuZCByZWluZm9yY2VtZW50cw==").should == "Send reinforcements"
  end

  it "returns the Base64-decoded version of the given shared string" do
    Base64.strict_decode64("base64: U2VuZCByZWluZm9yY2VtZW50cw==".split(" ").last).should == "Send reinforcements"
  end

  it "raises ArgumentError when the given string contains CR" do
    -> do
      Base64.strict_decode64("U2VuZCByZWluZm9yY2VtZW50cw==\r")
    end.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when the given string contains LF" do
    -> do
      Base64.strict_decode64("U2VuZCByZWluZm9yY2VtZW50cw==\n")
    end.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when the given string has wrong padding" do
    -> do
      Base64.strict_decode64("=U2VuZCByZWluZm9yY2VtZW50cw==")
    end.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when the given string contains an invalid character" do
    -> do
      Base64.strict_decode64("%3D")
    end.should raise_error(ArgumentError)
  end

  it "returns a binary encoded string" do
    Base64.strict_decode64("SEk=").encoding.should == Encoding::BINARY
  end
end
