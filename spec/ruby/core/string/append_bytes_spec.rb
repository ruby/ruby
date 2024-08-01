require_relative '../../spec_helper'

describe "String#append_bytes" do
  ruby_version_is "3.4" do
    it "allows creating broken strings" do
      str = +"hello"
      str.append_bytes("\xE2\x82")
      str.valid_encoding?.should == false

      str.append_bytes("\xAC")
      str.valid_encoding?.should == true

      str = "abc".encode(Encoding::UTF_32LE)
      str.append_bytes("def")
      str.encoding.should == Encoding::UTF_32LE
      str.valid_encoding?.should == false
    end

    it "never changes the receiver encoding" do
      str = "".b
      str.append_bytes("€")
      str.encoding.should == Encoding::BINARY
    end

    it "only accepts strings, and doesn't attempt to cast with #to_str" do
      to_str = mock("to_str")
      to_str.should_not_receive(:to_str)

      str = +"hello"
      -> { str.append_bytes(to_str) }.should raise_error(TypeError, "wrong argument type MockObject (expected String)")
    end
  end
end
