require_relative '../../spec_helper'

describe "Integer#to_s" do
  context "fixnum" do
    context "when given a base" do
      it "returns self converted to a String in the given base" do
        12345.to_s(2).should == "11000000111001"
        12345.to_s(8).should == "30071"
        12345.to_s(10).should == "12345"
        12345.to_s(16).should == "3039"
        95.to_s(16).should == "5f"
        12345.to_s(36).should == "9ix"
      end

      it "raises an ArgumentError if the base is less than 2 or higher than 36" do
        -> { 123.to_s(-1) }.should raise_error(ArgumentError)
        -> { 123.to_s(0)  }.should raise_error(ArgumentError)
        -> { 123.to_s(1)  }.should raise_error(ArgumentError)
        -> { 123.to_s(37) }.should raise_error(ArgumentError)
      end
    end

    context "when no base given" do
      it "returns self converted to a String using base 10" do
        255.to_s.should == '255'
        3.to_s.should == '3'
        0.to_s.should == '0'
        -9002.to_s.should == '-9002'
      end
    end

    before :each do
      @internal = Encoding.default_internal
    end

    after :each do
      Encoding.default_internal = @internal
    end

    it "returns a String in US-ASCII encoding when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      1.to_s.encoding.should equal(Encoding::US_ASCII)
    end

    it "returns a String in US-ASCII encoding when Encoding.default_internal is not nil" do
      Encoding.default_internal = Encoding::IBM437
      1.to_s.encoding.should equal(Encoding::US_ASCII)
    end
  end

  context "bignum" do
    describe "when given a base" do
      it "returns self converted to a String using the given base" do
        a = 2**64
        a.to_s(2).should == "10000000000000000000000000000000000000000000000000000000000000000"
        a.to_s(8).should == "2000000000000000000000"
        a.to_s(16).should == "10000000000000000"
        a.to_s(32).should == "g000000000000"
      end

      it "raises an ArgumentError if the base is less than 2 or higher than 36" do
        -> { 123.to_s(-1) }.should raise_error(ArgumentError)
        -> { 123.to_s(0) }.should raise_error(ArgumentError)
        -> { 123.to_s(1) }.should raise_error(ArgumentError)
        -> { 123.to_s(37) }.should raise_error(ArgumentError)
      end
    end

    describe "when given no base" do
      it "returns self converted to a String using base 10" do
        bignum_value(9).to_s.should == "9223372036854775817"
        bignum_value.to_s.should == "9223372036854775808"
        (-bignum_value(675)).to_s.should == "-9223372036854776483"
      end
    end

    before :each do
      @internal = Encoding.default_internal
    end

    after :each do
      Encoding.default_internal = @internal
    end

    it "returns a String in US-ASCII encoding when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      bignum_value.to_s.encoding.should equal(Encoding::US_ASCII)
    end

    it "returns a String in US-ASCII encoding when Encoding.default_internal is not nil" do
      Encoding.default_internal = Encoding::IBM437
      bignum_value.to_s.encoding.should equal(Encoding::US_ASCII)
    end
  end
end
