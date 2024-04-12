# encoding: utf-8
# frozen_string_literal: false

require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#reverse" do
  it "returns a new string with the characters of self in reverse order" do
    "stressed".reverse.should == "desserts"
    "m".reverse.should == "m"
    "".reverse.should == ""
  end

  it "returns String instances when called on a subclass" do
    StringSpecs::MyString.new("stressed").reverse.should be_an_instance_of(String)
    StringSpecs::MyString.new("m").reverse.should be_an_instance_of(String)
    StringSpecs::MyString.new("").reverse.should be_an_instance_of(String)
  end

  it "reverses a string with multi byte characters" do
    "微軟正黑體".reverse.should == "體黑正軟微"
  end

  it "works with a broken string" do
    str = "微軟\xDF\xDE正黑體".force_encoding(Encoding::UTF_8)

    str.valid_encoding?.should be_false

    str.reverse.should == "體黑正\xDE\xDF軟微"
  end

  it "returns a String in the same encoding as self" do
    "stressed".encode("US-ASCII").reverse.encoding.should == Encoding::US_ASCII
  end
end

describe "String#reverse!" do
  it "reverses self in place and always returns self" do
    a = "stressed"
    a.reverse!.should equal(a)
    a.should == "desserts"

    "".reverse!.should == ""
  end

  it "raises a FrozenError on a frozen instance that is modified" do
    -> { "anna".freeze.reverse!  }.should raise_error(FrozenError)
    -> { "hello".freeze.reverse! }.should raise_error(FrozenError)
  end

  # see [ruby-core:23666]
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "".freeze.reverse! }.should raise_error(FrozenError)
  end

  it "reverses a string with multi byte characters" do
    str = "微軟正黑體"
    str.reverse!
    str.should == "體黑正軟微"
  end

  it "works with a broken string" do
    str = "微軟\xDF\xDE正黑體".force_encoding(Encoding::UTF_8)

    str.valid_encoding?.should be_false
    str.reverse!

    str.should == "體黑正\xDE\xDF軟微"
  end
end
