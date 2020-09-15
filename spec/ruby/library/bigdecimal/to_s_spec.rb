require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal#to_s" do

  before :each do
    @bigdec_str = "3.14159265358979323846264338327950288419716939937"
    @bigneg_str = "-3.1415926535897932384626433832795028841971693993"
    @bigdec = BigDecimal(@bigdec_str)
    @bigneg = BigDecimal(@bigneg_str)
    @internal = Encoding.default_internal
  end

  after :each do
    Encoding.default_internal = @internal
  end

  it "return type is of class String" do
    @bigdec.to_s.kind_of?(String).should == true
    @bigneg.to_s.kind_of?(String).should == true
  end

  it "the default format looks like 0.xxxxenn" do
    @bigdec.to_s.should =~ /^0\.[0-9]*e[0-9]*$/
  end

  it "does not add an exponent for zero values" do
    BigDecimal("0").to_s.should == "0.0"
    BigDecimal("+0").to_s.should == "0.0"
    BigDecimal("-0").to_s.should == "-0.0"
  end

  it "takes an optional argument" do
    -> {@bigdec.to_s("F")}.should_not raise_error()
  end

  it "starts with + if + is supplied and value is positive" do
    @bigdec.to_s("+").should =~ /^\+.*/
    @bigneg.to_s("+").should_not =~ /^\+.*/
  end

  it "inserts a space every n chars, if integer n is supplied" do
    re =\
      /\A0\.314 159 265 358 979 323 846 264 338 327 950 288 419 716 939 937E1\z/i
    @bigdec.to_s(3).should =~ re

    str1 = '-123.45678 90123 45678 9'
    BigDecimal("-123.45678901234567890").to_s('5F').should ==  str1
    BigDecimal('1000010').to_s('5F').should == "10000 10.0"
    # trailing zeroes removed
    BigDecimal("1.00000000000").to_s('1F').should == "1.0"
    # 0 is treated as no spaces
    BigDecimal("1.2345").to_s('0F').should == "1.2345"
  end

  it "can return a leading space for values > 0" do
    @bigdec.to_s(" F").should =~ /\ .*/
    @bigneg.to_s(" F").should_not =~ /\ .*/
  end

  it "removes trailing spaces in floating point notation" do
    BigDecimal('-123.45678901234567890').to_s('F').should == "-123.4567890123456789"
    BigDecimal('1.2500').to_s('F').should == "1.25"
    BigDecimal('0000.00000').to_s('F').should == "0.0"
    BigDecimal('-00.000010000').to_s('F').should == "-0.00001"
    BigDecimal("5.00000E-2").to_s("F").should == "0.05"

    BigDecimal("500000").to_s("F").should == "500000.0"
    BigDecimal("5E2").to_s("F").should == "500.0"
    BigDecimal("-5E100").to_s("F").should == "-5" + "0" * 100 + ".0"
  end

  it "can use engineering notation" do
    @bigdec.to_s("E").should =~ /^0\.[0-9]*E[0-9]*$/i
  end

  it "can use conventional floating point notation" do
    %w[f F].each do |format_char|
      @bigdec.to_s(format_char).should == @bigdec_str
      @bigneg.to_s(format_char).should == @bigneg_str
      str2 = "+123.45678901 23456789"
      BigDecimal('123.45678901234567890').to_s("+8#{format_char}").should == str2
    end
  end

  ruby_version_is "3.0" do
    it "returns a String in US-ASCII encoding when Encoding.default_internal is nil" do
      Encoding.default_internal = nil
      BigDecimal('1.23').to_s.encoding.should equal(Encoding::US_ASCII)
    end

    it "returns a String in US-ASCII encoding when Encoding.default_internal is not nil" do
      Encoding.default_internal = Encoding::IBM437
      BigDecimal('1.23').to_s.encoding.should equal(Encoding::US_ASCII)
    end
  end
end
