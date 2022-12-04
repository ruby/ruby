require_relative '../../spec_helper'
require_relative '../../fixtures/rational'

describe :kernel_Rational, shared: true do
  describe "passed Integer" do
    # Guard against the Mathn library
    guard -> { !defined?(Math.rsqrt) } do
      it "returns a new Rational number with 1 as the denominator" do
        Rational(1).should eql(Rational(1, 1))
        Rational(-3).should eql(Rational(-3, 1))
        Rational(bignum_value).should eql(Rational(bignum_value, 1))
      end
    end
  end

  describe "passed two integers" do
    it "returns a new Rational number" do
      rat = Rational(1, 2)
      rat.numerator.should == 1
      rat.denominator.should == 2
      rat.should be_an_instance_of(Rational)

      rat = Rational(-3, -5)
      rat.numerator.should == 3
      rat.denominator.should == 5
      rat.should be_an_instance_of(Rational)

      rat = Rational(bignum_value, 3)
      rat.numerator.should == bignum_value
      rat.denominator.should == 3
      rat.should be_an_instance_of(Rational)
    end

    it "reduces the Rational" do
      rat = Rational(2, 4)
      rat.numerator.should == 1
      rat.denominator.should == 2

      rat = Rational(3, 9)
      rat.numerator.should == 1
      rat.denominator.should == 3
    end
  end

  describe "when passed a String" do
    it "converts the String to a Rational using the same method as String#to_r" do
      r = Rational(13, 25)
      s_r = ".52".to_r
      r_s = Rational(".52")

      r_s.should == r
      r_s.should == s_r
    end

    it "scales the Rational value of the first argument by the Rational value of the second" do
      Rational(".52", ".6").should == Rational(13, 15)
      Rational(".52", "1.6").should == Rational(13, 40)
    end

    it "does not use the same method as Float#to_r" do
      r = Rational(3, 5)
      f_r = 0.6.to_r
      r_s = Rational("0.6")

      r_s.should == r
      r_s.should_not == f_r
    end

    describe "when passed a Numeric" do
      it "calls #to_r to convert the first argument to a Rational" do
        num = RationalSpecs::SubNumeric.new(2)

        Rational(num).should == Rational(2)
      end
    end

    describe "when passed a Complex" do
      it "returns a Rational from the real part if the imaginary part is 0" do
        Rational(Complex(1, 0)).should == Rational(1)
      end

      it "raises a RangeError if the imaginary part is not 0" do
        -> { Rational(Complex(1, 2)) }.should raise_error(RangeError)
      end
    end

    it "raises a TypeError if the first argument is nil" do
      -> { Rational(nil) }.should raise_error(TypeError)
    end

    it "raises a TypeError if the second argument is nil" do
      -> { Rational(1, nil) }.should raise_error(TypeError)
    end

    it "raises a TypeError if the first argument is a Symbol" do
      -> { Rational(:sym) }.should raise_error(TypeError)
    end

    it "raises a TypeError if the second argument is a Symbol" do
      -> { Rational(1, :sym) }.should raise_error(TypeError)
    end
  end

  describe "when passed exception: false" do
    describe "and [non-Numeric]" do
      it "swallows an error" do
        Rational(:sym, exception: false).should == nil
        Rational("abc", exception: false).should == nil
      end
    end

    describe "and [non-Numeric, Numeric]" do
      it "swallows an error" do
        Rational(:sym, 1, exception: false).should == nil
        Rational("abc", 1, exception: false).should == nil
      end
    end

    describe "and [anything, non-Numeric]" do
      it "swallows an error" do
        Rational(:sym, :sym, exception: false).should == nil
        Rational("abc", :sym, exception: false).should == nil
      end
    end

    describe "and non-Numeric String arguments" do
      it "swallows an error" do
        Rational("a", "b", exception: false).should == nil
        Rational("a", 0, exception: false).should == nil
        Rational(0, "b", exception: false).should == nil
      end
    end

    describe "and nil arguments" do
      it "swallows an error" do
        Rational(nil, exception: false).should == nil
        Rational(nil, nil, exception: false).should == nil
      end
    end
  end
end
