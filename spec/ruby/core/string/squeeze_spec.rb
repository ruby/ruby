# encoding: binary
# frozen_string_literal: false
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# TODO: rewrite all these specs

describe "String#squeeze" do
  it "returns new string where runs of the same character are replaced by a single character when no args are given" do
    "yellow moon".squeeze.should == "yelow mon"
  end

  it "only squeezes chars that are in the intersection of all sets given" do
    "woot squeeze cheese".squeeze("eost", "queo").should == "wot squeze chese"
    "  now   is  the".squeeze(" ").should == " now is the"
  end

  it "negates sets starting with ^" do
    s = "<<subbookkeeper!!!>>"
    s.squeeze("beko", "^e").should == s.squeeze("bko")
    s.squeeze("^<bek!>").should == s.squeeze("o")
    s.squeeze("^o").should == s.squeeze("<bek!>")
    s.squeeze("^").should == s
    "^__^".squeeze("^^").should == "^_^"
    "((^^__^^))".squeeze("_^").should == "((^_^))"
  end

  it "squeezes all chars in a sequence" do
    s = "--subbookkeeper--"
    s.squeeze("\x00-\xFF").should == s.squeeze
    s.squeeze("bk-o").should == s.squeeze("bklmno")
    s.squeeze("b-e").should == s.squeeze("bcde")
    s.squeeze("e-").should == "-subbookkeper-"
    s.squeeze("-e").should == "-subbookkeper-"
    s.squeeze("---").should == "-subbookkeeper-"
    "ook--001122".squeeze("--2").should == "ook-012"
    "ook--(())".squeeze("(--").should == "ook-()"
    s.squeeze("^b-e").should == "-subbokeeper-"
    "^^__^^".squeeze("^^-^").should == "^^_^^"
    "^^--^^".squeeze("^---").should == "^--^"

    s.squeeze("b-dk-o-").should == "-subokeeper-"
    s.squeeze("-b-dk-o").should == "-subokeeper-"
    s.squeeze("b-d-k-o").should == "-subokeeper-"

    s.squeeze("bc-e").should == "--subookkeper--"
    s.squeeze("^bc-e").should == "-subbokeeper-"

    "AABBCCaabbcc[[]]".squeeze("A-a").should == "ABCabbcc[]"
  end

  it "raises an ArgumentError when the parameter is out of sequence" do
    s = "--subbookkeeper--"
    -> { s.squeeze("e-b") }.should raise_error(ArgumentError)
    -> { s.squeeze("^e-b") }.should raise_error(ArgumentError)
  end

  it "tries to convert each set arg to a string using to_str" do
    other_string = mock('lo')
    other_string.should_receive(:to_str).and_return("lo")

    other_string2 = mock('o')
    other_string2.should_receive(:to_str).and_return("o")

    "hello room".squeeze(other_string, other_string2).should == "hello rom"
  end

  it "returns a String in the same encoding as self" do
    "yellow moon".encode("US-ASCII").squeeze.encoding.should == Encoding::US_ASCII
    "yellow moon".encode("US-ASCII").squeeze("a").encoding.should == Encoding::US_ASCII
  end

  it "raises a TypeError when one set arg can't be converted to a string" do
    -> { "hello world".squeeze([])        }.should raise_error(TypeError)
    -> { "hello world".squeeze(Object.new)}.should raise_error(TypeError)
    -> { "hello world".squeeze(mock('x')) }.should raise_error(TypeError)
  end

  it "returns String instances when called on a subclass" do
    StringSpecs::MyString.new("oh no!!!").squeeze("!").should be_an_instance_of(String)
  end
end

describe "String#squeeze!" do
  it "modifies self in place and returns self" do
    a = "yellow moon"
    a.squeeze!.should equal(a)
    a.should == "yelow mon"
  end

  it "returns nil if no modifications were made" do
    a = "squeeze"
    a.squeeze!("u", "sq").should == nil
    a.squeeze!("q").should == nil
    a.should == "squeeze"
  end

  it "raises an ArgumentError when the parameter is out of sequence" do
    s = "--subbookkeeper--"
    -> { s.squeeze!("e-b") }.should raise_error(ArgumentError)
    -> { s.squeeze!("^e-b") }.should raise_error(ArgumentError)
  end

  it "raises a FrozenError when self is frozen" do
    a = "yellow moon"
    a.freeze

    -> { a.squeeze!("") }.should raise_error(FrozenError)
    -> { a.squeeze!     }.should raise_error(FrozenError)
  end
end
