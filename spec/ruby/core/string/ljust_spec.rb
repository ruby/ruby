# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#ljust with length, padding" do
  it "returns a new string of specified length with self left justified and padded with padstr" do
    "hello".ljust(20, '1234').should == "hello123412341234123"

    "".ljust(1, "abcd").should == "a"
    "".ljust(2, "abcd").should == "ab"
    "".ljust(3, "abcd").should == "abc"
    "".ljust(4, "abcd").should == "abcd"
    "".ljust(6, "abcd").should == "abcdab"

    "OK".ljust(3, "abcd").should == "OKa"
    "OK".ljust(4, "abcd").should == "OKab"
    "OK".ljust(6, "abcd").should == "OKabcd"
    "OK".ljust(8, "abcd").should == "OKabcdab"
  end

  it "pads with whitespace if no padstr is given" do
    "hello".ljust(20).should == "hello               "
  end

  it "returns self if it's longer than or as long as the specified length" do
    "".ljust(0).should == ""
    "".ljust(-1).should == ""
    "hello".ljust(4).should == "hello"
    "hello".ljust(-1).should == "hello"
    "this".ljust(3).should == "this"
    "radiology".ljust(8, '-').should == "radiology"
  end

  it "tries to convert length to an integer using to_int" do
    "^".ljust(3.8, "_^").should == "^_^"

    obj = mock('3')
    obj.should_receive(:to_int).and_return(3)

    "o".ljust(obj, "_o").should == "o_o"
  end

  it "raises a TypeError when length can't be converted to an integer" do
    -> { "hello".ljust("x")       }.should raise_error(TypeError)
    -> { "hello".ljust("x", "y")  }.should raise_error(TypeError)
    -> { "hello".ljust([])        }.should raise_error(TypeError)
    -> { "hello".ljust(mock('x')) }.should raise_error(TypeError)
  end

  it "tries to convert padstr to a string using to_str" do
    padstr = mock('123')
    padstr.should_receive(:to_str).and_return("123")

    "hello".ljust(10, padstr).should == "hello12312"
  end

  it "raises a TypeError when padstr can't be converted" do
    -> { "hello".ljust(20, [])        }.should raise_error(TypeError)
    -> { "hello".ljust(20, Object.new)}.should raise_error(TypeError)
    -> { "hello".ljust(20, mock('x')) }.should raise_error(TypeError)
  end

  it "raises an ArgumentError when padstr is empty" do
    -> { "hello".ljust(10, '') }.should raise_error(ArgumentError)
  end

  it "returns String instances when called on subclasses" do
    StringSpecs::MyString.new("").ljust(10).should be_an_instance_of(String)
    StringSpecs::MyString.new("foo").ljust(10).should be_an_instance_of(String)
    StringSpecs::MyString.new("foo").ljust(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)

    "".ljust(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)
    "foo".ljust(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)
  end

  describe "with width" do
    it "returns a String in the same encoding as the original" do
      str = "abc".force_encoding Encoding::IBM437
      result = str.ljust 5
      result.should == "abc  "
      result.encoding.should equal(Encoding::IBM437)
    end
  end

  describe "with width, pattern" do
    it "returns a String in the compatible encoding" do
      str = "abc".force_encoding Encoding::IBM437
      result = str.ljust 5, "あ"
      result.should == "abcああ"
      result.encoding.should equal(Encoding::UTF_8)
    end

    it "raises an Encoding::CompatibilityError if the encodings are incompatible" do
      pat = "ア".encode Encoding::EUC_JP
      -> do
        "あれ".ljust 5, pat
      end.should raise_error(Encoding::CompatibilityError)
    end
  end
end
