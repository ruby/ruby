require_relative '../../spec_helper'

require 'base64'

describe "Base64#decode64" do
  it "returns the Base64-decoded version of the given string" do
    Base64.decode64("U2VuZCByZWluZm9yY2VtZW50cw==\n").should == "Send reinforcements"
  end

  it "returns the Base64-decoded version of the given shared string" do
    Base64.decode64("base64: U2VuZCByZWluZm9yY2VtZW50cw==\n".split(" ").last).should == "Send reinforcements"
  end

  it "returns the Base64-decoded version of the given string with wrong padding" do
    Base64.decode64("XU2VuZCByZWluZm9yY2VtZW50cw===").should == "]M\x95\xB9\x90\x81\xC9\x95\xA5\xB9\x99\xBD\xC9\x8D\x95\xB5\x95\xB9\xD1\xCC".b
  end

  it "returns the Base64-decoded version of the given string that contains an invalid character" do
    Base64.decode64("%3D").should == "\xDC".b
  end

  it "returns a binary encoded string" do
    Base64.decode64("SEk=").encoding.should == Encoding::BINARY
  end

  it "decodes without padding suffix ==" do
    Base64.decode64("eyJrZXkiOnsibiI6InR0dCJ9fQ").should == "{\"key\":{\"n\":\"ttt\"}}"
  end
end
