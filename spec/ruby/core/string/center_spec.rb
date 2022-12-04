# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#center with length, padding" do
  it "returns a new string of specified length with self centered and padded with padstr" do
    "one".center(9, '.').should == "...one..."
    "hello".center(20, '123').should == "1231231hello12312312"
    "middle".center(13, '-').should == "---middle----"

    "".center(1, "abcd").should == "a"
    "".center(2, "abcd").should == "aa"
    "".center(3, "abcd").should == "aab"
    "".center(4, "abcd").should == "abab"
    "".center(6, "xy").should == "xyxxyx"
    "".center(11, "12345").should == "12345123451"

    "|".center(2, "abcd").should == "|a"
    "|".center(3, "abcd").should == "a|a"
    "|".center(4, "abcd").should == "a|ab"
    "|".center(5, "abcd").should == "ab|ab"
    "|".center(6, "xy").should == "xy|xyx"
    "|".center(7, "xy").should == "xyx|xyx"
    "|".center(11, "12345").should == "12345|12345"
    "|".center(12, "12345").should == "12345|123451"

    "||".center(3, "abcd").should == "||a"
    "||".center(4, "abcd").should == "a||a"
    "||".center(5, "abcd").should == "a||ab"
    "||".center(6, "abcd").should == "ab||ab"
    "||".center(8, "xy").should == "xyx||xyx"
    "||".center(12, "12345").should == "12345||12345"
    "||".center(13, "12345").should == "12345||123451"
  end

  it "pads with whitespace if no padstr is given" do
    "two".center(5).should == " two "
    "hello".center(20).should == "       hello        "
  end

  it "returns self if it's longer than or as long as the specified length" do
    "".center(0).should == ""
    "".center(-1).should == ""
    "hello".center(4).should == "hello"
    "hello".center(-1).should == "hello"
    "this".center(3).should == "this"
    "radiology".center(8, '-').should == "radiology"
  end

  it "calls #to_int to convert length to an integer" do
    "_".center(3.8, "^").should == "^_^"

    obj = mock('3')
    obj.should_receive(:to_int).and_return(3)

    "_".center(obj, "o").should == "o_o"
  end

  it "raises a TypeError when length can't be converted to an integer" do
    -> { "hello".center("x")       }.should raise_error(TypeError)
    -> { "hello".center("x", "y")  }.should raise_error(TypeError)
    -> { "hello".center([])        }.should raise_error(TypeError)
    -> { "hello".center(mock('x')) }.should raise_error(TypeError)
  end

  it "calls #to_str to convert padstr to a String" do
    padstr = mock('123')
    padstr.should_receive(:to_str).and_return("123")

    "hello".center(20, padstr).should == "1231231hello12312312"
  end

  it "raises a TypeError when padstr can't be converted to a string" do
    -> { "hello".center(20, 100)       }.should raise_error(TypeError)
    -> { "hello".center(20, [])      }.should raise_error(TypeError)
    -> { "hello".center(20, mock('x')) }.should raise_error(TypeError)
  end

  it "raises an ArgumentError if padstr is empty" do
    -> { "hello".center(10, "") }.should raise_error(ArgumentError)
    -> { "hello".center(0, "")  }.should raise_error(ArgumentError)
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances when called on subclasses" do
      StringSpecs::MyString.new("").center(10).should be_an_instance_of(StringSpecs::MyString)
      StringSpecs::MyString.new("foo").center(10).should be_an_instance_of(StringSpecs::MyString)
      StringSpecs::MyString.new("foo").center(10, StringSpecs::MyString.new("x")).should be_an_instance_of(StringSpecs::MyString)

      "".center(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)
      "foo".center(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)
    end
  end

  ruby_version_is '3.0' do
    it "returns String instances when called on subclasses" do
      StringSpecs::MyString.new("").center(10).should be_an_instance_of(String)
      StringSpecs::MyString.new("foo").center(10).should be_an_instance_of(String)
      StringSpecs::MyString.new("foo").center(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)

      "".center(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)
      "foo".center(10, StringSpecs::MyString.new("x")).should be_an_instance_of(String)
    end
  end

  describe "with width" do
    it "returns a String in the same encoding as the original" do
      str = "abc".force_encoding Encoding::IBM437
      result = str.center 6
      result.should == " abc  "
      result.encoding.should equal(Encoding::IBM437)
    end
  end

  describe "with width, pattern" do
    it "returns a String in the compatible encoding" do
      str = "abc".force_encoding Encoding::IBM437
      result = str.center 6, "あ"
      result.should == "あabcああ"
      result.encoding.should equal(Encoding::UTF_8)
    end

    it "raises an Encoding::CompatibilityError if the encodings are incompatible" do
      pat = "ア".encode Encoding::EUC_JP
      -> do
        "あれ".center 5, pat
      end.should raise_error(Encoding::CompatibilityError)
    end
  end
end
