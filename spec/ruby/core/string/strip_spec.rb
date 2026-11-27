# frozen_string_literal: false
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/strip'

describe "String#strip" do
  it_behaves_like :string_strip, :strip

  it "returns a new string with leading and trailing whitespace removed" do
    "   hello   ".strip.should == "hello"
    "   hello world   ".strip.should == "hello world"
    "\tgoodbye\r\v\n".strip.should == "goodbye"
  end

  it "returns a copy of self without leading and trailing NULL bytes and whitespace" do
    " \x00 goodbye \x00 ".strip.should == "goodbye"
  end

  ruby_version_is "4.0" do
    context "when given character selectors arguments" do
      it "removes leading and trailing characters in the intersection of sets removed" do
        "  hello  ".strip(" ").should == "hello"
        "llo".strip("lo", "l").should == "o"
        "llo".strip("o", "lo").should == "ll"
        "hello".strip("ho", "h").should == "ello"
        "hell yeah".strip("").should == "hell yeah"
      end

      it "negates sets starting with ^" do
        "ello".strip("aeiou", "^e").should == "ell"
        "hello".strip("^o").should == "o"
      end

      it "removes leading and trailing characters in a sequence" do
        "hello".strip("l-o").should == "he"
        "hello".strip("e-h").should == "llo"
        "hel-lo".strip("h-").should == "el-lo"
        "hel-lo".strip("-o").should == "hel-l"
        "abcdefgh".strip("a-ce-fh").should == "defg"
        "abcdefgh".strip("he-fa-c").should == "defg"
        "abcdefgh".strip("e-fha-c").should == "defg"
        "abcde".strip("ac-e").should == "b"
        "abcde".strip("^ac-e").should == "abcde"
      end

      it "removes leading and trailing multibyte characters" do
        "四月".strip("月").should == "四"
        "四月".strip("四").should == "月"
        "哥哥我倒".strip("哥").should == "我倒"
      end

      it "respects backslash for escaping" do
        "a-b".strip("a\\-b").should == ""
        "^".strip("\\^").should == ""
        "\\".strip("\\\\").should == ""
      end

      it "raises an ArgumentError when the sequence is invalid" do
        -> { "hello".strip("h-e") }.should.raise(ArgumentError)
        -> { "hello".strip("^h-e") }.should.raise(ArgumentError)
      end

      it "tries to convert each argument to a string using to_str" do
        other_string = mock('h')
        other_string.should_receive(:to_str).and_return("h")

        other_string2 = mock('he')
        other_string2.should_receive(:to_str).and_return("he")

        "hello world".strip(other_string, other_string2).should == "ello world"
      end

      it "raises a TypeError when an argument can't be converted to a string" do
        -> { "hello world".strip(100)       }.should.raise(TypeError)
        -> { "hello world".strip([])        }.should.raise(TypeError)
        -> { "hello world".strip(mock('x')) }.should.raise(TypeError)
      end

      it "returns String instances when called on a subclass" do
        StringSpecs::MyString.new("oh no!!!").strip("!").should.instance_of?(String)
      end

      it "returns a String in the same encoding as self" do
        "hello".encode("US-ASCII").strip("h").encoding.should == Encoding::US_ASCII
      end

      it "raises an Encoding::CompatibilityError when the encodings are incompatible" do
        -> { "hello".strip("e".encode("UTF-16LE")) }.should.raise(Encoding::CompatibilityError)
        -> { "hello".encode("UTF-16LE").strip("e") }.should.raise(Encoding::CompatibilityError)
      end
    end
  end
end

describe "String#strip!" do
  it "modifies self in place and returns self" do
    a = "   hello   "
    a.strip!.should.equal?(a)
    a.should == "hello"

    ruby_version_is "4.0" do
      a = "---goodbye---"
      a.strip!("-")
      a.should == "goodbye"
    end
  end

  it "returns nil if no modifications where made" do
    a = "hello"
    a.strip!.should == nil
    a.should == "hello"

    ruby_version_is "4.0" do
      a = "hello"
      a.strip!("-").should == nil
      a.should == "hello"
    end
  end

  it "makes a string empty if it is only whitespace" do
    a = ""
    a.strip!
    a.should == ""

    a = "   "
    a.strip!
    a.should == ""
  end

  ruby_version_is "4.0" do
    it "makes a string empty if all characters match given character selectors" do
      a = ""
      a.strip!("-")
      a.should == ""

      a = "----"
      a.strip!("-")
      a.should == ""
    end
  end

  it "removes leading and trailing NULL bytes and whitespace" do
    a = "\000 goodbye \000"
    a.strip!
    a.should == "goodbye"
  end

  it "raises a FrozenError on a frozen instance that is modified" do
    -> { "  hello  ".freeze.strip! }.should.raise(FrozenError)
    ruby_version_is "4.0" do
      -> { "  hello  ".freeze.strip!("-") }.should.raise(FrozenError)
    end
  end

  # see #1552
  it "raises a FrozenError on a frozen instance that would not be modified" do
    -> {"hello".freeze.strip! }.should.raise(FrozenError)
    -> {"".freeze.strip!      }.should.raise(FrozenError)
  end
end
