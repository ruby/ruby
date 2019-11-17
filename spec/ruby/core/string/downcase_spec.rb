# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#downcase" do
  it "returns a copy of self with all uppercase letters downcased" do
    "hELLO".downcase.should == "hello"
    "hello".downcase.should == "hello"
  end

  describe "full Unicode case mapping" do
    it "works for all of Unicode with no option" do
      "ÄÖÜ".downcase.should == "äöü"
    end

    it "updates string metadata" do
      downcased = "\u{212A}ING".downcase

      downcased.should == "king"
      downcased.size.should == 4
      downcased.bytesize.should == 4
      downcased.ascii_only?.should be_true
    end
  end

  describe "ASCII-only case mapping" do
    it "does not downcase non-ASCII characters" do
      "CÅR".downcase(:ascii).should == "cÅr"
    end
  end

  describe "full Unicode case mapping adapted for Turkic languages" do
    it "downcases characters according to Turkic semantics" do
      "İ".downcase(:turkic).should == "i"
    end

    it "allows Lithuanian as an extra option" do
      "İ".downcase(:turkic, :lithuanian).should == "i"
    end

    it "does not allow any other additional option" do
      -> { "İ".downcase(:turkic, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "full Unicode case mapping adapted for Lithuanian" do
    it "currently works the same as full Unicode case mapping" do
      "İS".downcase(:lithuanian).should == "i\u{307}s"
    end

    it "allows Turkic as an extra option (and applies Turkic semantics)" do
      "İS".downcase(:lithuanian, :turkic).should == "is"
    end

    it "does not allow any other additional option" do
      -> { "İS".downcase(:lithuanian, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "case folding" do
    it "case folds special characters" do
      "ß".downcase.should == "ß"
      "ß".downcase(:fold).should == "ss"
    end
  end

  it "does not allow invalid options" do
    -> { "ABC".downcase(:invalid_option) }.should raise_error(ArgumentError)
  end

  ruby_version_is ''...'2.7' do
    it "taints result when self is tainted" do
      "".taint.downcase.tainted?.should == true
      "x".taint.downcase.tainted?.should == true
      "X".taint.downcase.tainted?.should == true
    end
  end

  it "returns a subclass instance for subclasses" do
    StringSpecs::MyString.new("FOObar").downcase.should be_an_instance_of(StringSpecs::MyString)
  end
end

describe "String#downcase!" do
  it "modifies self in place" do
    a = "HeLlO"
    a.downcase!.should equal(a)
    a.should == "hello"
  end

  describe "full Unicode case mapping" do
    it "modifies self in place for all of Unicode with no option" do
      a = "ÄÖÜ"
      a.downcase!
      a.should == "äöü"
    end

    it "updates string metadata" do
      downcased = "\u{212A}ING"
      downcased.downcase!

      downcased.should == "king"
      downcased.size.should == 4
      downcased.bytesize.should == 4
      downcased.ascii_only?.should be_true
    end
  end

  describe "ASCII-only case mapping" do
    it "does not downcase non-ASCII characters" do
      a = "CÅR"
      a.downcase!(:ascii)
      a.should == "cÅr"
    end
  end

  describe "full Unicode case mapping adapted for Turkic languages" do
    it "downcases characters according to Turkic semantics" do
      a = "İ"
      a.downcase!(:turkic)
      a.should == "i"
    end

    it "allows Lithuanian as an extra option" do
      a = "İ"
      a.downcase!(:turkic, :lithuanian)
      a.should == "i"
    end

    it "does not allow any other additional option" do
      -> { a = "İ"; a.downcase!(:turkic, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "full Unicode case mapping adapted for Lithuanian" do
    it "currently works the same as full Unicode case mapping" do
      a = "İS"
      a.downcase!(:lithuanian)
      a.should == "i\u{307}s"
    end

    it "allows Turkic as an extra option (and applies Turkic semantics)" do
      a = "İS"
      a.downcase!(:lithuanian, :turkic)
      a.should == "is"
    end

    it "does not allow any other additional option" do
      -> { a = "İS"; a.downcase!(:lithuanian, :ascii) }.should raise_error(ArgumentError)
    end
  end

  describe "case folding" do
    it "case folds special characters" do
      a = "ß"
      a.downcase!
      a.should == "ß"

      a.downcase!(:fold)
      a.should == "ss"
    end
  end

  it "does not allow invalid options" do
    -> { a = "ABC"; a.downcase!(:invalid_option) }.should raise_error(ArgumentError)
  end

  it "returns nil if no modifications were made" do
    a = "hello"
    a.downcase!.should == nil
    a.should == "hello"
  end

  it "raises a #{frozen_error_class} when self is frozen" do
    -> { "HeLlo".freeze.downcase! }.should raise_error(frozen_error_class)
    -> { "hello".freeze.downcase! }.should raise_error(frozen_error_class)
  end

  it "sets the result String encoding to the source String encoding" do
    "ABC".downcase.encoding.should equal(Encoding::UTF_8)
  end
end
