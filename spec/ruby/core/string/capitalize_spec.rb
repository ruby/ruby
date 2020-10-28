# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#capitalize" do
  it "returns a copy of self with the first character converted to uppercase and the remainder to lowercase" do
    "".capitalize.should == ""
    "h".capitalize.should == "H"
    "H".capitalize.should == "H"
    "hello".capitalize.should == "Hello"
    "HELLO".capitalize.should == "Hello"
    "123ABC".capitalize.should == "123abc"
  end

  ruby_version_is ''...'2.7' do
    it "taints resulting string when self is tainted" do
      "".taint.capitalize.should.tainted?
      "hello".taint.capitalize.should.tainted?
    end
  end

  describe "full Unicode case mapping" do
    it "works for all of Unicode with no option" do
      "äöÜ".capitalize.should == "Äöü"
    end

    it "only capitalizes the first resulting character when upcasing a character produces a multi-character sequence" do
      "ß".capitalize.should == "Ss"
    end

    it "updates string metadata" do
      capitalized = "ßeT".capitalize

      capitalized.should == "Sset"
      capitalized.size.should == 4
      capitalized.bytesize.should == 4
      capitalized.ascii_only?.should be_true
    end
  end

  describe "ASCII-only case mapping" do
    it "does not capitalize non-ASCII characters" do
      "ßet".capitalize(:ascii).should == "ßet"
    end
  end

  describe "full Unicode case mapping adapted for Turkic languages" do
    it "capitalizes ASCII characters according to Turkic semantics" do
      "iSa".capitalize(:turkic).should == "İsa"
    end

    it "allows Lithuanian as an extra option" do
      "iSa".capitalize(:turkic, :lithuanian).should == "İsa"
    end

    it "does not allow any other additional option" do
      -> { "iSa".capitalize(:turkic, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "full Unicode case mapping adapted for Lithuanian" do
    it "currently works the same as full Unicode case mapping" do
      "iß".capitalize(:lithuanian).should == "Iß"
    end

    it "allows Turkic as an extra option (and applies Turkic semantics)" do
      "iß".capitalize(:lithuanian, :turkic).should == "İß"
    end

    it "does not allow any other additional option" do
      -> { "iß".capitalize(:lithuanian, :ascii) }.should raise_error(ArgumentError)
    end
  end

  it "does not allow the :fold option for upcasing" do
    -> { "abc".capitalize(:fold) }.should raise_error(ArgumentError)
  end

  it "does not allow invalid options" do
    -> { "abc".capitalize(:invalid_option) }.should raise_error(ArgumentError)
  end

  it "returns subclass instances when called on a subclass" do
    StringSpecs::MyString.new("hello").capitalize.should be_an_instance_of(StringSpecs::MyString)
    StringSpecs::MyString.new("Hello").capitalize.should be_an_instance_of(StringSpecs::MyString)
  end
end

describe "String#capitalize!" do
  it "capitalizes self in place" do
    a = "hello"
    a.capitalize!.should equal(a)
    a.should == "Hello"
  end

  it "modifies self in place for non-ascii-compatible encodings" do
    a = "heLLo".encode("utf-16le")
    a.capitalize!
    a.should == "Hello".encode("utf-16le")
  end

  describe "full Unicode case mapping" do
    it "modifies self in place for all of Unicode with no option" do
      a = "äöÜ"
      a.capitalize!
      a.should == "Äöü"
    end

    it "only capitalizes the first resulting character when upcasing a character produces a multi-character sequence" do
      a = "ß"
      a.capitalize!
      a.should == "Ss"
    end

    it "works for non-ascii-compatible encodings" do
      a = "äöü".encode("utf-16le")
      a.capitalize!
      a.should == "Äöü".encode("utf-16le")
    end

    it "updates string metadata" do
      capitalized = "ßeT"
      capitalized.capitalize!

      capitalized.should == "Sset"
      capitalized.size.should == 4
      capitalized.bytesize.should == 4
      capitalized.ascii_only?.should be_true
    end
  end

  describe "modifies self in place for ASCII-only case mapping" do
    it "does not capitalize non-ASCII characters" do
      a = "ßet"
      a.capitalize!(:ascii)
      a.should == "ßet"
    end

    it "works for non-ascii-compatible encodings" do
      a = "aBc".encode("utf-16le")
      a.capitalize!(:ascii)
      a.should == "Abc".encode("utf-16le")
    end
  end

  describe "modifies self in place for full Unicode case mapping adapted for Turkic languages" do
    it "capitalizes ASCII characters according to Turkic semantics" do
      a = "iSa"
      a.capitalize!(:turkic)
      a.should == "İsa"
    end

    it "allows Lithuanian as an extra option" do
      a = "iSa"
      a.capitalize!(:turkic, :lithuanian)
      a.should == "İsa"
    end

    it "does not allow any other additional option" do
      -> { a = "iSa"; a.capitalize!(:turkic, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "modifies self in place for full Unicode case mapping adapted for Lithuanian" do
    it "currently works the same as full Unicode case mapping" do
      a = "iß"
      a.capitalize!(:lithuanian)
      a.should == "Iß"
    end

    it "allows Turkic as an extra option (and applies Turkic semantics)" do
      a = "iß"
      a.capitalize!(:lithuanian, :turkic)
      a.should == "İß"
    end

    it "does not allow any other additional option" do
      -> { a = "iß"; a.capitalize!(:lithuanian, :ascii) }.should raise_error(ArgumentError)
    end
  end

  it "does not allow the :fold option for upcasing" do
    -> { a = "abc"; a.capitalize!(:fold) }.should raise_error(ArgumentError)
  end

  it "does not allow invalid options" do
    -> { a = "abc"; a.capitalize!(:invalid_option) }.should raise_error(ArgumentError)
  end

  it "returns nil when no changes are made" do
    a = "Hello"
    a.capitalize!.should == nil
    a.should == "Hello"

    "".capitalize!.should == nil
    "H".capitalize!.should == nil
  end

  it "raises a FrozenError when self is frozen" do
    ["", "Hello", "hello"].each do |a|
      a.freeze
      -> { a.capitalize! }.should raise_error(FrozenError)
    end
  end
end
