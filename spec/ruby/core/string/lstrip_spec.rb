require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/strip'

describe "String#lstrip" do
  it_behaves_like :string_strip, :lstrip

  it "returns a copy of self with leading whitespace removed" do
   "  hello  ".lstrip.should == "hello  "
   "  hello world  ".lstrip.should == "hello world  "
   "\n\r\t\n\v\r hello world  ".lstrip.should == "hello world  "
   "hello".lstrip.should == "hello"
   " こにちわ".lstrip.should == "こにちわ"
  end

  it "works with lazy substrings" do
    "  hello  "[1...-1].lstrip.should == "hello "
    "  hello world  "[1...-1].lstrip.should == "hello world "
    "\n\r\t\n\v\r hello world  "[1...-1].lstrip.should == "hello world "
    "   こにちわ "[1...-1].lstrip.should == "こにちわ"
  end

  it "strips leading \\0" do
   "\x00hello".lstrip.should == "hello"
   "\000 \000hello\000 \000".lstrip.should == "hello\000 \000"
  end
end

describe "String#lstrip!" do
  it "modifies self in place and returns self" do
    a = "  hello  "
    a.lstrip!.should equal(a)
    a.should == "hello  "
  end

  it "returns nil if no modifications were made" do
    a = "hello"
    a.lstrip!.should == nil
    a.should == "hello"
  end

  it "makes a string empty if it is only whitespace" do
    "".lstrip!.should == nil
    " ".lstrip.should == ""
    "  ".lstrip.should == ""
  end

  it "removes leading NULL bytes and whitespace" do
    a = "\000 \000hello\000 \000"
    a.lstrip!
    a.should == "hello\000 \000"
  end

  it "raises a FrozenError on a frozen instance that is modified" do
    -> { "  hello  ".freeze.lstrip! }.should raise_error(FrozenError)
  end

  # see [ruby-core:23657]
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "hello".freeze.lstrip! }.should raise_error(FrozenError)
    -> { "".freeze.lstrip!      }.should raise_error(FrozenError)
  end

  it "raises an ArgumentError if the first non-space codepoint is invalid" do
    s = "\xDFabc".force_encoding(Encoding::UTF_8)
    s.valid_encoding?.should be_false
    -> { s.lstrip! }.should raise_error(ArgumentError)

    s = "   \xDFabc".force_encoding(Encoding::UTF_8)
    s.valid_encoding?.should be_false
    -> { s.lstrip! }.should raise_error(ArgumentError)
  end
end
