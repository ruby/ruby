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

  ruby_version_is "4.0" do
    context "when given character selectors arguments" do
      it "removes trailing characters in the intersection of sets removed" do
        "  hello  ".rstrip(" ").should == "  hello"
        "llo".rstrip("o", "lo").should == "ll"
        "hell yeah".rstrip("").should == "hell yeah"
      end

      it "negates sets starting with ^" do
        "ello".rstrip("aeiou", "^o").should == "ello"
        "hello".rstrip("^h").should == "h"
      end

      it "removes trailing characters in a sequence" do
        "hello".rstrip("l-o").should == "he"
        "hel-lo".rstrip("h-").should == "hel-lo"
        "abcdefgh".rstrip("a-ce-fh").should == "abcdefg"
        "abcde".rstrip("ac-e").should == "ab"
      end

      it "removes trailing multibyte characters" do
        "四月".rstrip("月").should == "四"
        "哥哥我倒".rstrip("倒").should == "哥哥我"
      end

      it "respects backslash for escaping" do
        "a-b".rstrip("a\\-b").should == ""
        "^".rstrip("\\^").should == ""
        "\\".rstrip("\\\\").should == ""
      end

      it "raises an ArgumentError when the sequence is invalid" do
        -> { "hello".rstrip("h-e") }.should.raise(ArgumentError)
        -> { "hello".rstrip("^h-e") }.should.raise(ArgumentError)
      end

      it "tries to convert each argument to a string using to_str" do
        other_string = mock('d')
        other_string.should_receive(:to_str).and_return("d")

        other_string2 = mock('ld')
        other_string2.should_receive(:to_str).and_return("ld")

        "hello world".rstrip(other_string, other_string2).should == "hello worl"
      end

      it "raises a TypeError when an argument can't be converted to a string" do
        -> { "hello world".rstrip(100)       }.should.raise(TypeError)
        -> { "hello world".rstrip([])        }.should.raise(TypeError)
        -> { "hello world".rstrip(mock('x')) }.should.raise(TypeError)
      end

      it "returns String instances when called on a subclass" do
        StringSpecs::MyString.new("oh no!!!").rstrip("!").should.instance_of?(String)
      end

      it "returns a String in the same encoding as self" do
        "hello".encode("US-ASCII").rstrip("o").encoding.should == Encoding::US_ASCII
      end

      it "raises an Encoding::CompatibilityError when the encodings are incompatible" do
        -> { "hello".rstrip("e".encode("UTF-16LE")) }.should.raise(Encoding::CompatibilityError)
        -> { "hello".encode("UTF-16LE").rstrip("e") }.should.raise(Encoding::CompatibilityError)
      end
    end
  end
end

describe "String#rstrip!" do
  it "modifies self in place and returns self" do
    a = "  hello  "
    a.rstrip!.should.equal?(a)
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
    -> { "  hello  ".freeze.rstrip! }.should.raise(FrozenError)
  end

  # see [ruby-core:23666]
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "hello".freeze.rstrip! }.should.raise(FrozenError)
    -> { "".freeze.rstrip!      }.should.raise(FrozenError)
  end

  it "raises an Encoding::CompatibilityError if the last non-space codepoint is invalid" do
    s = "abc\xDF".force_encoding(Encoding::UTF_8)
    s.valid_encoding?.should == false
    -> { s.rstrip! }.should.raise(Encoding::CompatibilityError)

    s = "abc\xDF   ".force_encoding(Encoding::UTF_8)
    s.valid_encoding?.should == false
    -> { s.rstrip! }.should.raise(Encoding::CompatibilityError)
  end
end
