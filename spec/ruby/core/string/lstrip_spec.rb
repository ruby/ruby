# frozen_string_literal: false
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

  ruby_version_is "4.0" do
    context "when given character selectors arguments" do
      it "removes leading characters in the intersection of sets removed" do
        "  hello  ".lstrip(" ").should == "hello  "
        "llo".lstrip("lo", "l").should == "o"
        "hello".lstrip("ho", "h").should == "ello"
        "hell yeah".lstrip("").should == "hell yeah"
      end

      it "negates sets starting with ^" do
        "ello".lstrip("aeiou", "^e").should == "ello"
        "hello".lstrip("^o").should == "o"
      end

      it "removes leading characters in a sequence" do
        "hello".lstrip("e-h").should == "llo"
        "hel-lo".lstrip("h-").should == "el-lo"
        "abcdefgh".lstrip("a-ce-fh").should == "defgh"
        "abcde".lstrip("ac-e").should == "bcde"
      end

      it "removes leading multibyte characters" do
        "四月".lstrip("四").should == "月"
        "哥哥我倒".lstrip("哥").should == "我倒"
      end

      it "respects backslash for escaping" do
        "a-b".lstrip("a\\-b").should == ""
        "^".lstrip("\\^").should == ""
        "\\".lstrip("\\\\").should == ""
      end

      it "raises an ArgumentError when the sequence is invalid" do
        -> { "hello".lstrip("h-e") }.should.raise(ArgumentError)
        -> { "hello".lstrip("^h-e") }.should.raise(ArgumentError)
      end

      it "tries to convert each argument to a string using to_str" do
        other_string = mock('h')
        other_string.should_receive(:to_str).and_return("h")

        other_string2 = mock('he')
        other_string2.should_receive(:to_str).and_return("he")

        "hello world".lstrip(other_string, other_string2).should == "ello world"
      end

      it "raises a TypeError when an argument can't be converted to a string" do
        -> { "hello world".lstrip(100)       }.should.raise(TypeError)
        -> { "hello world".lstrip([])        }.should.raise(TypeError)
        -> { "hello world".lstrip(mock('x')) }.should.raise(TypeError)
      end

      it "returns String instances when called on a subclass" do
        StringSpecs::MyString.new("oh no!!!").lstrip("o").should.instance_of?(String)
      end

      it "returns a String in the same encoding as self" do
        "hello".encode("US-ASCII").lstrip("h").encoding.should == Encoding::US_ASCII
      end

      it "raises an Encoding::CompatibilityError when the encodings are incompatible" do
        -> { "hello".lstrip("e".encode("UTF-16LE")) }.should.raise(Encoding::CompatibilityError)
        -> { "hello".encode("UTF-16LE").lstrip("e") }.should.raise(Encoding::CompatibilityError)
      end
    end
  end
end

describe "String#lstrip!" do
  it "modifies self in place and returns self" do
    a = "  hello  "
    a.lstrip!.should.equal?(a)
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
    -> { "  hello  ".freeze.lstrip! }.should.raise(FrozenError)
  end

  # see [ruby-core:23657]
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> { "hello".freeze.lstrip! }.should.raise(FrozenError)
    -> { "".freeze.lstrip!      }.should.raise(FrozenError)
  end

  it "raises an ArgumentError if the first non-space codepoint is invalid" do
    s = "\xDFabc".force_encoding(Encoding::UTF_8)
    s.valid_encoding?.should == false
    -> { s.lstrip! }.should.raise(ArgumentError)

    s = "   \xDFabc".force_encoding(Encoding::UTF_8)
    s.valid_encoding?.should == false
    -> { s.lstrip! }.should.raise(ArgumentError)
  end
end
