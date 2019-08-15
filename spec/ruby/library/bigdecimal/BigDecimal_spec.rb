require_relative '../../spec_helper'
require 'bigdecimal'

describe "BigDecimal" do
  it "is not defined unless it is required" do
    ruby_exe('puts Object.const_defined?(:BigDecimal)').should == "false\n"
  end
end

describe "Kernel#BigDecimal" do

  it "creates a new object of class BigDecimal" do
    BigDecimal("3.14159").should be_kind_of(BigDecimal)
    (0..9).each {|i|
      BigDecimal("1#{i}").should == 10 + i
      BigDecimal("-1#{i}").should == -10 - i
      BigDecimal("1E#{i}").should == 10**i
      BigDecimal("1000000E-#{i}").should == 10**(6-i).to_f
      # ^ to_f to avoid Rational type
    }
    (1..9).each {|i|
      BigDecimal("100.#{i}").to_s.should =~ /\A0\.100#{i}E3\z/i
      BigDecimal("-100.#{i}").to_s.should =~ /\A-0\.100#{i}E3\z/i
    }
  end

  it "accepts significant digits >= given precision" do
    BigDecimal("3.1415923", 10).precs[1].should >= 10
  end

  it "determines precision from initial value" do
    pi_string = "3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651328230664709384460955058223172535940812848111745028410270193852110555964462294895493038196442881097566593014782083152134043"
    BigDecimal(pi_string).precs[1].should >= pi_string.size-1
  end

  it "ignores leading whitespace" do
    BigDecimal("  \t\n \r1234").should == BigDecimal("1234")
    BigDecimal("  \t\n \rNaN   \n").nan?.should == true
    BigDecimal("  \t\n \rInfinity   \n").infinite?.should == 1
    BigDecimal("  \t\n \r-Infinity   \n").infinite?.should == -1
  end

  ruby_version_is ""..."2.6" do
    it "ignores trailing garbage" do
      BigDecimal("123E45ruby").should == BigDecimal("123E45")
      BigDecimal("123x45").should == BigDecimal("123")
      BigDecimal("123.4%E5").should == BigDecimal("123.4")
      BigDecimal("1E2E3E4E5E").should == BigDecimal("100")
    end
  end

  ruby_version_is "2.6" do
    it "does not ignores trailing garbage" do
      -> { BigDecimal("123E45ruby") }.should raise_error(ArgumentError)
      -> { BigDecimal("123x45") }.should raise_error(ArgumentError)
      -> { BigDecimal("123.4%E5") }.should raise_error(ArgumentError)
      -> { BigDecimal("1E2E3E4E5E") }.should raise_error(ArgumentError)
    end
  end

  it "raises ArgumentError for invalid strings" do
    -> { BigDecimal("ruby") }.should raise_error(ArgumentError)
    -> { BigDecimal("  \t\n \r-\t\t\tInfinity   \n") }.should raise_error(ArgumentError)
  end

  it "allows omitting the integer part" do
    BigDecimal(".123").should == BigDecimal("0.123")
  end

  ruby_version_is ""..."2.6" do
    it "allows for underscores in all parts" do
      reference = BigDecimal("12345.67E89")

      BigDecimal("12_345.67E89").should == reference
      BigDecimal("1_2_3_4_5_._6____7_E89").should == reference
      BigDecimal("12345_.67E_8__9_").should == reference
    end
  end

  ruby_version_is "2.6" do
    it "process underscores as Float()" do
      reference = BigDecimal("12345.67E89")

      BigDecimal("12_345.67E89").should == reference
      -> { BigDecimal("1_2_3_4_5_._6____7_E89") }.should raise_error(ArgumentError)
      -> { BigDecimal("12345_.67E_8__9_") }.should raise_error(ArgumentError)
    end
  end

  it "accepts NaN and [+-]Infinity" do
    BigDecimal("NaN").nan?.should == true

    pos_inf = BigDecimal("Infinity")
    pos_inf.finite?.should == false
    pos_inf.should > 0
    pos_inf.should == BigDecimal("+Infinity")

    neg_inf = BigDecimal("-Infinity")
    neg_inf.finite?.should == false
    neg_inf.should < 0
  end

  describe "accepts NaN and [+-]Infinity as Float values" do
    it "works without an explicit precision" do
      BigDecimal(Float::NAN).nan?.should == true

      pos_inf = BigDecimal(Float::INFINITY)
      pos_inf.finite?.should == false
      pos_inf.should > 0
      pos_inf.should == BigDecimal("+Infinity")

      neg_inf = BigDecimal(-Float::INFINITY)
      neg_inf.finite?.should == false
      neg_inf.should < 0
    end

    it "works with an explicit precision" do
      BigDecimal(Float::NAN, Float::DIG).nan?.should == true

      pos_inf = BigDecimal(Float::INFINITY, Float::DIG)
      pos_inf.finite?.should == false
      pos_inf.should > 0
      pos_inf.should == BigDecimal("+Infinity")

      neg_inf = BigDecimal(-Float::INFINITY, Float::DIG)
      neg_inf.finite?.should == false
      neg_inf.should < 0
    end
  end

  it "allows for [eEdD] as exponent separator" do
    reference = BigDecimal("12345.67E89")

    BigDecimal("12345.67e89").should == reference
    BigDecimal("12345.67E89").should == reference
    BigDecimal("12345.67d89").should == reference
    BigDecimal("12345.67D89").should == reference
  end

  it "allows for varying signs" do
    reference = BigDecimal("123.456E1")

    BigDecimal("+123.456E1").should == reference
    BigDecimal("-123.456E1").should == -reference
    BigDecimal("123.456E+1").should == reference
    BigDecimal("12345.6E-1").should == reference
    BigDecimal("+123.456E+1").should == reference
    BigDecimal("+12345.6E-1").should == reference
    BigDecimal("-123.456E+1").should == -reference
    BigDecimal("-12345.6E-1").should == -reference
  end

  it "raises ArgumentError when Float is used without precision" do
    -> { BigDecimal(1.0) }.should raise_error(ArgumentError)
  end

  it "returns appropriate BigDecimal zero for signed zero" do
    BigDecimal(-0.0, Float::DIG).sign.should == -1
    BigDecimal(0.0, Float::DIG).sign.should == 1
  end

end
