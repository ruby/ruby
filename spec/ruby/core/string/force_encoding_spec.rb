# frozen_string_literal: false
require_relative '../../spec_helper'

describe "String#force_encoding" do
  it "accepts a String as the name of an Encoding" do
    "abc".force_encoding('shift_jis').encoding.should == Encoding::Shift_JIS
  end

  describe "with a special encoding name" do
    before :each do
      @original_encoding = Encoding.default_internal
    end

    after :each do
      Encoding.default_internal = @original_encoding
    end

    it "accepts valid special encoding names" do
      Encoding.default_internal = "US-ASCII"
      "abc".force_encoding("internal").encoding.should == Encoding::US_ASCII
    end

    it "defaults to BINARY if special encoding name is not set" do
      Encoding.default_internal = nil
      "abc".force_encoding("internal").encoding.should == Encoding::BINARY
    end
  end

  it "accepts an Encoding instance" do
    "abc".force_encoding(Encoding::SHIFT_JIS).encoding.should == Encoding::Shift_JIS
  end

  it "calls #to_str to convert an object to an encoding name" do
    obj = mock("force_encoding")
    obj.should_receive(:to_str).and_return("utf-8")

    "abc".force_encoding(obj).encoding.should == Encoding::UTF_8
  end

  it "raises a TypeError if #to_str does not return a String" do
    obj = mock("force_encoding")
    obj.should_receive(:to_str).and_return(1)

    -> { "abc".force_encoding(obj) }.should raise_error(TypeError)
  end

  it "raises a TypeError if passed nil" do
    -> { "abc".force_encoding(nil) }.should raise_error(TypeError)
  end

  it "returns self" do
    str = "abc"
    str.force_encoding('utf-8').should equal(str)
  end

  it "sets the encoding even if the String contents are invalid in that encoding" do
    str = "\u{9765}"
    str.force_encoding('euc-jp')
    str.encoding.should == Encoding::EUC_JP
    str.valid_encoding?.should be_false
  end

  it "does not transcode self" do
    str = "é"
    str.dup.force_encoding('utf-16le').should_not == str.encode('utf-16le')
  end

  it "raises a FrozenError if self is frozen" do
    str = "abcd".freeze
    -> { str.force_encoding(str.encoding) }.should raise_error(FrozenError)
  end
end
