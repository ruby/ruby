# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#swapcase" do
  it "returns a new string with all uppercase chars from self converted to lowercase and vice versa" do
   "Hello".swapcase.should == "hELLO"
   "cYbEr_PuNk11".swapcase.should == "CyBeR_pUnK11"
   "+++---111222???".swapcase.should == "+++---111222???"
  end

  it "taints resulting string when self is tainted" do
    "".taint.swapcase.tainted?.should == true
    "hello".taint.swapcase.tainted?.should == true
  end

  ruby_version_is ''...'2.4' do
    it "is locale insensitive (only upcases a-z and only downcases A-Z)" do
      "ÄÖÜ".swapcase.should == "ÄÖÜ"
      "ärger".swapcase.should == "äRGER"
      "BÄR".swapcase.should == "bÄr"
    end
  end

  ruby_version_is '2.4' do
    describe "full Unicode case mapping" do
      it "works for all of Unicode with no option" do
        "äÖü".swapcase.should == "ÄöÜ"
      end

      it "updates string metadata" do
        swapcased = "Aßet".swapcase

        swapcased.should == "aSSET"
        swapcased.size.should == 5
        swapcased.bytesize.should == 5
        swapcased.ascii_only?.should be_true
      end
    end

    describe "ASCII-only case mapping" do
      it "does not swapcase non-ASCII characters" do
        "aßet".swapcase(:ascii).should == "AßET"
      end
    end

    describe "full Unicode case mapping adapted for Turkic languages" do
      it "swaps case of ASCII characters according to Turkic semantics" do
        "aiS".swapcase(:turkic).should == "Aİs"
      end

      it "allows Lithuanian as an extra option" do
        "aiS".swapcase(:turkic, :lithuanian).should == "Aİs"
      end

      it "does not allow any other additional option" do
        lambda { "aiS".swapcase(:turkic, :ascii) }.should raise_error(ArgumentError)
      end
    end

    describe "full Unicode case mapping adapted for Lithuanian" do
      it "currently works the same as full Unicode case mapping" do
        "Iß".swapcase(:lithuanian).should == "iSS"
      end

      it "allows Turkic as an extra option (and applies Turkic semantics)" do
        "iS".swapcase(:lithuanian, :turkic).should == "İs"
      end

      it "does not allow any other additional option" do
        lambda { "aiS".swapcase(:lithuanian, :ascii) }.should raise_error(ArgumentError)
      end
    end

    it "does not allow the :fold option for upcasing" do
      lambda { "abc".swapcase(:fold) }.should raise_error(ArgumentError)
    end

    it "does not allow invalid options" do
      lambda { "abc".swapcase(:invalid_option) }.should raise_error(ArgumentError)
    end
  end

  it "returns subclass instances when called on a subclass" do
    StringSpecs::MyString.new("").swapcase.should be_an_instance_of(StringSpecs::MyString)
    StringSpecs::MyString.new("hello").swapcase.should be_an_instance_of(StringSpecs::MyString)
  end
end

describe "String#swapcase!" do
  it "modifies self in place" do
    a = "cYbEr_PuNk11"
    a.swapcase!.should equal(a)
    a.should == "CyBeR_pUnK11"
  end

  ruby_version_is '2.4' do
    describe "full Unicode case mapping" do
      it "modifies self in place for all of Unicode with no option" do
        a = "äÖü"
        a.swapcase!
        a.should == "ÄöÜ"
      end

      it "updates string metadata" do
        swapcased = "Aßet"
        swapcased.swapcase!

        swapcased.should == "aSSET"
        swapcased.size.should == 5
        swapcased.bytesize.should == 5
        swapcased.ascii_only?.should be_true
      end
    end

    describe "modifies self in place for ASCII-only case mapping" do
      it "does not swapcase non-ASCII characters" do
        a = "aßet"
        a.swapcase!(:ascii)
        a.should == "AßET"
      end
    end

    describe "modifies self in place for full Unicode case mapping adapted for Turkic languages" do
      it "swaps case of ASCII characters according to Turkic semantics" do
        a = "aiS"
        a.swapcase!(:turkic)
        a.should == "Aİs"
      end

      it "allows Lithuanian as an extra option" do
        a = "aiS"
        a.swapcase!(:turkic, :lithuanian)
        a.should == "Aİs"
      end

      it "does not allow any other additional option" do
        lambda { a = "aiS"; a.swapcase!(:turkic, :ascii) }.should raise_error(ArgumentError)
      end
    end

    describe "full Unicode case mapping adapted for Lithuanian" do
      it "currently works the same as full Unicode case mapping" do
        a = "Iß"
        a.swapcase!(:lithuanian)
        a.should == "iSS"
      end

      it "allows Turkic as an extra option (and applies Turkic semantics)" do
        a = "iS"
        a.swapcase!(:lithuanian, :turkic)
        a.should == "İs"
      end

      it "does not allow any other additional option" do
        lambda { a = "aiS"; a.swapcase!(:lithuanian, :ascii) }.should raise_error(ArgumentError)
      end
    end

    it "does not allow the :fold option for upcasing" do
      lambda { a = "abc"; a.swapcase!(:fold) }.should raise_error(ArgumentError)
    end

    it "does not allow invalid options" do
      lambda { a = "abc"; a.swapcase!(:invalid_option) }.should raise_error(ArgumentError)
    end
  end

  it "returns nil if no modifications were made" do
    a = "+++---111222???"
    a.swapcase!.should == nil
    a.should == "+++---111222???"

    "".swapcase!.should == nil
  end

  it "raises a #{frozen_error_class} when self is frozen" do
    ["", "hello"].each do |a|
      a.freeze
      lambda { a.swapcase! }.should raise_error(frozen_error_class)
    end
  end
end
