require_relative '../../spec_helper'

describe "String#append_bytes" do
  ruby_version_is "3.4" do
    it "doesn't allow to mutate frozen strings" do
      str = "hello".freeze
      -> { str.append_as_bytes("\xE2\x82") }.should raise_error(FrozenError)
    end

    it "allows creating broken strings" do
      str = +"hello"
      str.append_as_bytes("\xE2\x82")
      str.valid_encoding?.should == false

      str.append_as_bytes("\xAC")
      str.valid_encoding?.should == true

      str = "abc".encode(Encoding::UTF_32LE)
      str.append_as_bytes("def")
      str.encoding.should == Encoding::UTF_32LE
      str.valid_encoding?.should == false
    end

    it "never changes the receiver encoding" do
      str = "".b
      str.append_as_bytes("€")
      str.encoding.should == Encoding::BINARY
    end

    it "accepts variadic String or Integer arguments" do
      str = "hello".b
      str.append_as_bytes("\xE2\x82", 12, 43, "\xAC")
      str.encoding.should == Encoding::BINARY
      str.should == "hello\xE2\x82\f+\xAC".b
    end

    it "only accepts strings or integers, and doesn't attempt to cast with #to_str or #to_int" do
      to_str = mock("to_str")
      to_str.should_not_receive(:to_str)
      to_str.should_not_receive(:to_int)

      str = +"hello"
      -> { str.append_as_bytes(to_str) }.should raise_error(TypeError, "wrong argument type MockObject (expected String or Integer)")
    end
  end
end
