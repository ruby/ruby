# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#upcase" do
  it "returns a copy of self with all lowercase letters upcased" do
    "Hello".upcase.should == "HELLO"
    "hello".upcase.should == "HELLO"
  end

  it "returns a String in the same encoding as self" do
    "hello".encode("US-ASCII").upcase.encoding.should == Encoding::US_ASCII
  end

  describe "full Unicode case mapping" do
    it "works for all of Unicode with no option" do
      "äöü".upcase.should == "ÄÖÜ"
    end

    it "updates string metadata" do
      upcased = "aßet".upcase

      upcased.should == "ASSET"
      upcased.size.should == 5
      upcased.bytesize.should == 5
      upcased.ascii_only?.should be_true
    end
  end

  describe "ASCII-only case mapping" do
    it "does not upcase non-ASCII characters" do
      "aßet".upcase(:ascii).should == "AßET"
    end

    it "works with substrings" do
      "prefix té"[-2..-1].upcase(:ascii).should == "Té"
    end
  end

  describe "full Unicode case mapping adapted for Turkic languages" do
    it "upcases ASCII characters according to Turkic semantics" do
      "i".upcase(:turkic).should == "İ"
    end

    it "allows Lithuanian as an extra option" do
      "i".upcase(:turkic, :lithuanian).should == "İ"
    end

    it "does not allow any other additional option" do
      -> { "i".upcase(:turkic, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "full Unicode case mapping adapted for Lithuanian" do
    it "currently works the same as full Unicode case mapping" do
      "iß".upcase(:lithuanian).should == "ISS"
    end

    it "allows Turkic as an extra option (and applies Turkic semantics)" do
      "iß".upcase(:lithuanian, :turkic).should == "İSS"
    end

    it "does not allow any other additional option" do
      -> { "iß".upcase(:lithuanian, :ascii) }.should raise_error(ArgumentError)
    end
  end

  it "does not allow the :fold option for upcasing" do
    -> { "abc".upcase(:fold) }.should raise_error(ArgumentError)
  end

  it "does not allow invalid options" do
    -> { "abc".upcase(:invalid_option) }.should raise_error(ArgumentError)
  end

  it "returns a String instance for subclasses" do
    StringSpecs::MyString.new("fooBAR").upcase.should be_an_instance_of(String)
  end
end

describe "String#upcase!" do
  it "modifies self in place" do
    a = "HeLlO"
    a.upcase!.should equal(a)
    a.should == "HELLO"
  end

  it "modifies self in place for non-ascii-compatible encodings" do
    a = "HeLlO".encode("utf-16le")
    a.upcase!
    a.should == "HELLO".encode("utf-16le")
  end

  describe "full Unicode case mapping" do
    it "modifies self in place for all of Unicode with no option" do
      a = "äöü"
      a.upcase!
      a.should == "ÄÖÜ"
    end

    it "works for non-ascii-compatible encodings" do
      a = "äöü".encode("utf-16le")
      a.upcase!
      a.should == "ÄÖÜ".encode("utf-16le")
    end

    it "updates string metadata for self" do
      upcased = "aßet"
      upcased.upcase!

      upcased.should == "ASSET"
      upcased.size.should == 5
      upcased.bytesize.should == 5
      upcased.ascii_only?.should be_true
    end
  end

  describe "modifies self in place for ASCII-only case mapping" do
    it "does not upcase non-ASCII characters" do
      a = "aßet"
      a.upcase!(:ascii)
      a.should == "AßET"
    end

    it "works for non-ascii-compatible encodings" do
      a = "abc".encode("utf-16le")
      a.upcase!(:ascii)
      a.should == "ABC".encode("utf-16le")
    end
  end

  describe "modifies self in place for full Unicode case mapping adapted for Turkic languages" do
    it "upcases ASCII characters according to Turkic semantics" do
      a = "i"
      a.upcase!(:turkic)
      a.should == "İ"
    end

    it "allows Lithuanian as an extra option" do
      a = "i"
      a.upcase!(:turkic, :lithuanian)
      a.should == "İ"
    end

    it "does not allow any other additional option" do
      -> { a = "i"; a.upcase!(:turkic, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "modifies self in place for full Unicode case mapping adapted for Lithuanian" do
    it "currently works the same as full Unicode case mapping" do
      a = "iß"
      a.upcase!(:lithuanian)
      a.should == "ISS"
    end

    it "allows Turkic as an extra option (and applies Turkic semantics)" do
      a = "iß"
      a.upcase!(:lithuanian, :turkic)
      a.should == "İSS"
    end

    it "does not allow any other additional option" do
      -> { a = "iß"; a.upcase!(:lithuanian, :ascii) }.should raise_error(ArgumentError)
    end
  end

  it "does not allow the :fold option for upcasing" do
    -> { a = "abc"; a.upcase!(:fold) }.should raise_error(ArgumentError)
  end

  it "does not allow invalid options" do
    -> { a = "abc"; a.upcase!(:invalid_option) }.should raise_error(ArgumentError)
  end

  it "returns nil if no modifications were made" do
    a = "HELLO"
    a.upcase!.should == nil
    a.should == "HELLO"
  end

  it "raises a FrozenError when self is frozen" do
    -> { "HeLlo".freeze.upcase! }.should raise_error(FrozenError)
    -> { "HELLO".freeze.upcase! }.should raise_error(FrozenError)
  end
end
