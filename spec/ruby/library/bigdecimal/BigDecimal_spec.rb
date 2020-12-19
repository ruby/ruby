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

  it "BigDecimal(Rational) with bigger-than-double numerator" do
    rational = 99999999999999999999/100r
    rational.numerator.should > 2**64
    BigDecimal(rational, 100).to_s.should == "0.99999999999999999999e18"
  end

  ruby_version_is ""..."3.0" do
    it "accepts significant digits >= given precision" do
      BigDecimal("3.1415923", 10).precs[1].should >= 10
    end

    it "determines precision from initial value" do
      pi_string = "3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651328230664709384460955058223172535940812848111745028410270193852110555964462294895493038196442881097566593014782083152134043"
      BigDecimal(pi_string).precs[1].should >= pi_string.size-1
    end
  end

  it "ignores leading and trailing whitespace" do
    BigDecimal("  \t\n \r1234\t\r\n ").should == BigDecimal("1234")
    BigDecimal("  \t\n \rNaN   \n").should.nan?
    BigDecimal("  \t\n \rInfinity   \n").infinite?.should == 1
    BigDecimal("  \t\n \r-Infinity   \n").infinite?.should == -1
  end

  it "coerces the value argument with #to_str" do
    initial = mock("value")
    initial.should_receive(:to_str).and_return("123")
    BigDecimal(initial).should == BigDecimal("123")
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
    BigDecimal("NaN").should.nan?

    pos_inf = BigDecimal("Infinity")
    pos_inf.should_not.finite?
    pos_inf.should > 0
    pos_inf.should == BigDecimal("+Infinity")

    neg_inf = BigDecimal("-Infinity")
    neg_inf.should_not.finite?
    neg_inf.should < 0
  end

  ruby_version_is "2.6" do
    describe "with exception: false" do
      it "returns nil for invalid strings" do
        BigDecimal("invalid", exception: false).should be_nil
        BigDecimal("0invalid", exception: false).should be_nil
        BigDecimal("invalid0", exception: false).should be_nil
        BigDecimal("0.", exception: false).should be_nil
      end
    end
  end

  describe "accepts NaN and [+-]Infinity as Float values" do
    it "works without an explicit precision" do
      BigDecimal(Float::NAN).should.nan?

      pos_inf = BigDecimal(Float::INFINITY)
      pos_inf.should_not.finite?
      pos_inf.should > 0
      pos_inf.should == BigDecimal("+Infinity")

      neg_inf = BigDecimal(-Float::INFINITY)
      neg_inf.should_not.finite?
      neg_inf.should < 0
    end

    it "works with an explicit precision" do
      BigDecimal(Float::NAN, Float::DIG).should.nan?

      pos_inf = BigDecimal(Float::INFINITY, Float::DIG)
      pos_inf.should_not.finite?
      pos_inf.should > 0
      pos_inf.should == BigDecimal("+Infinity")

      neg_inf = BigDecimal(-Float::INFINITY, Float::DIG)
      neg_inf.should_not.finite?
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

  it "pre-coerces long integers" do
    BigDecimal(3).add(1 << 50, 3).should == BigDecimal('0.113e16')
  end

  it "does not call to_s when calling inspect" do
    value = BigDecimal('44.44')
    value.to_s.should == '0.4444e2'
    value.inspect.should == '0.4444e2'

    ruby_exe( <<-'EOF').should == "cheese 0.4444e2"
      require 'bigdecimal'
      module BigDecimalOverride
        def to_s; "cheese"; end
      end
      BigDecimal.prepend BigDecimalOverride
      value = BigDecimal('44.44')
      print "#{value.to_s} #{value.inspect}"
    EOF
  end

  describe "when interacting with Rational" do
    before :each do
      @a = BigDecimal('166.666666666')
      @b = Rational(500, 3)
      @c = @a - @b
    end

    # Check the input is as we understand it

    it "has the LHS print as expected" do
      @a.to_s.should == "0.166666666666e3"
      @a.to_f.to_s.should == "166.666666666"
      Float(@a).to_s.should == "166.666666666"
    end

    it "has the RHS print as expected" do
      @b.to_s.should == "500/3"
      @b.to_f.to_s.should == "166.66666666666666"
      Float(@b).to_s.should == "166.66666666666666"
    end

    ruby_version_is ""..."3.0" do
      it "has the expected precision on the LHS" do
        @a.precs[0].should == 18
      end

      it "has the expected maximum precision on the LHS" do
        @a.precs[1].should == 27
      end
    end

    it "produces the expected result when done via Float" do
      (Float(@a) - Float(@b)).to_s.should == "-6.666596163995564e-10"
    end

    it "produces the expected result when done via to_f" do
      (@a.to_f - @b.to_f).to_s.should == "-6.666596163995564e-10"
    end

    # Check underlying methods work as we understand

    ruby_version_is ""..."3.0" do
      it "BigDecimal precision is the number of digits rounded up to a multiple of nine" do
        1.upto(100) do |n|
          b = BigDecimal('4' * n)
          precs, _ = b.precs
          (precs >= 9).should be_true
          (precs >= n).should be_true
          (precs % 9).should == 0
        end
        BigDecimal('NaN').precs[0].should == 9
      end

      it "BigDecimal maximum precision is nine more than precision except for abnormals" do
        1.upto(100) do |n|
          b = BigDecimal('4' * n)
          precs, max = b.precs
          max.should == precs + 9
        end
        BigDecimal('NaN').precs[1].should == 9
      end
    end

    it "BigDecimal(Rational, 18) produces the result we expect" do
      BigDecimal(@b, 18).to_s.should == "0.166666666666666667e3"
    end

    ruby_version_is ""..."3.0" do
      it "BigDecimal(Rational, BigDecimal.precs[0]) produces the result we expect" do
        BigDecimal(@b, @a.precs[0]).to_s.should == "0.166666666666666667e3"
      end
    end

    # Check the top-level expression works as we expect

    it "produces a BigDecimal" do
      @c.class.should == BigDecimal
    end

    it "produces the expected result" do
      @c.should == BigDecimal("-0.666667e-9")
      @c.to_s.should == "-0.666667e-9"
    end

    it "produces the correct class for other arithmetic operators" do
      (@a + @b).class.should == BigDecimal
      (@a * @b).class.should == BigDecimal
      (@a / @b).class.should == BigDecimal
      (@a % @b).class.should == BigDecimal
    end
  end
end
