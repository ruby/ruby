# frozen_string_literal: false
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/strip'

describe "String#rstrip" do
  it_behaves_like :string_strip, :rstrip

  it "returns a copy of self with trailing whitespace removed" do
    "  hello  ".rstrip.should == "  hello"
    "  hello world  ".rstrip.should == "  hello world"
    "  hello world \n\r\t\n\v\r".rstrip.should == "  hello world"
    "hello".rstrip.should == "hello"
    "hello\x00".rstrip.should == "hello"
    "こにちわ ".rstrip.should == "こにちわ"
  end

  it "works with lazy substrings" do
    "  hello  "[1...-1].rstrip.should == " hello"
    "  hello world  "[1...-1].rstrip.should == " hello world"
    "  hello world \n\r\t\n\v\r"[1...-1].rstrip.should == " hello world"
    " こにちわ  "[1...-1].rstrip.should == "こにちわ"
  end

  it "returns a copy of self with all trailing whitespace and NULL bytes removed" do
    "\x00 \x00hello\x00 \x00".rstrip.should == "\x00 \x00hello"
  end
end

describe "String#rstrip!" do
  it "modifies self in place and returns self" do
    a = "  hello  "
    a.rstrip!.should equal(a)
    a.should == "  hello"
  end

  it "modifies self removing trailing NULL bytes and whitespace" do
    a = "\x00 \x00hello\x00 \x00"
    a.rstrip!
    a.should == "\x00 \x00hello"
  end

  it "returns nil if no modifications were made" do
    a = "hello"
    a.rstrip!.should == nil
    a.should == "hello"
  end

  it "makes a string empty if it is only whitespace" do
    "".rstrip!.should == nil
    " ".rstrip.should == ""
    "  ".rstrip.should == ""
  end

  it "removes trailing NULL bytes and whitespace" do
    a = "\000 goodbye \000"
    a.rstrip!
    a.should == "\000 goodbye"
  end

  it "raises a FrozenError on a frozen instance that is modified" do
    -> { "  hello  ".freeze.rstrip! }.should raise_error(FrozenError)
  end

  # see [ruby-core:23666]
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "hello".freeze.rstrip! }.should raise_error(FrozenError)
    -> { "".freeze.rstrip!      }.should raise_error(FrozenError)
  end

  ruby_version_is "3.2" do
    it "raises an Encoding::CompatibilityError if the last non-space codepoint is invalid" do
      s = "abc\xDF".force_encoding(Encoding::UTF_8)
      s.valid_encoding?.should be_false
      -> { s.rstrip! }.should raise_error(Encoding::CompatibilityError)

      s = "abc\xDF   ".force_encoding(Encoding::UTF_8)
      s.valid_encoding?.should be_false
      -> { s.rstrip! }.should raise_error(Encoding::CompatibilityError)
    end
  end

  ruby_version_is ""..."3.2" do
    it "raises an ArgumentError if the last non-space codepoint is invalid" do
      s = "abc\xDF".force_encoding(Encoding::UTF_8)
      s.valid_encoding?.should be_false
      -> { s.rstrip! }.should raise_error(ArgumentError)

      s = "abc\xDF   ".force_encoding(Encoding::UTF_8)
      s.valid_encoding?.should be_false
      -> { s.rstrip! }.should raise_error(ArgumentError)
    end
  end
end
