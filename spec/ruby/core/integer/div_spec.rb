require_relative '../../spec_helper'

describe "Integer#div" do
  context "fixnum" do
    it "returns self divided by the given argument as an Integer" do
      2.div(2).should == 1
      1.div(2).should == 0
      5.div(2).should == 2
    end

    it "rounds towards -inf" do
      8192.div(10).should == 819
      8192.div(-10).should == -820
      (-8192).div(10).should == -820
      (-8192).div(-10).should == 819
    end

    it "means (x / y).floor" do
      5.div(2).should == (5 / 2).floor
      5.div(2.0).should == (5 / 2.0).floor
      5.div(-2).should == (5 / -2).floor

      5.div(100).should == (5 / 100).floor
      5.div(100.0).should == (5 / 100.0).floor
      5.div(-100).should == (5 / -100).floor
    end

    it "calls #coerce and #div if argument responds to #coerce" do
      x = mock("x")
      y = mock("y")
      result = mock("result")

      y.should_receive(:coerce).and_return([x, y])
      x.should_receive(:div).with(y).and_return(result)

      10.div(y).should == result
    end

    it "coerces self and the given argument to Floats and returns self divided by other as Integer" do
      1.div(0.2).should == 5
      1.div(0.16).should == 6
      1.div(0.169).should == 5
      -1.div(50.4).should == -1
      1.div(bignum_value).should == 0
      1.div(Rational(1, 5)).should == 5
    end

    it "raises a ZeroDivisionError when the given argument is 0 and a Float" do
      -> { 0.div(0.0)   }.should raise_error(ZeroDivisionError)
      -> { 10.div(0.0)  }.should raise_error(ZeroDivisionError)
      -> { -10.div(0.0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a ZeroDivisionError when the given argument is 0 and not a Float" do
      -> { 13.div(0) }.should raise_error(ZeroDivisionError)
      -> { 13.div(-0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a TypeError when given a non-numeric argument" do
      -> { 13.div(mock('10')) }.should raise_error(TypeError)
      -> { 5.div("2") }.should raise_error(TypeError)
      -> { 5.div(:"2") }.should raise_error(TypeError)
      -> { 5.div([]) }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(88)
    end

    it "returns self divided by other" do
      @bignum.div(4).should == 4611686018427387926
      @bignum.div(Rational(4, 1)).should == 4611686018427387926
      @bignum.div(bignum_value(2)).should == 1

      (-(10**50)).div(-(10**40 + 1)).should == 9999999999
      (10**50).div(10**40 + 1).should == 9999999999

      (-10**50).div(10**40 + 1).should == -10000000000
      (10**50).div(-(10**40 + 1)).should == -10000000000
    end

    it "handles fixnum_min / -1" do
      (fixnum_min / -1).should == -fixnum_min
      (fixnum_min / -1).should > 0

      int_min = -2147483648
      (int_min / -1).should == 2147483648
    end

    it "calls #coerce and #div if argument responds to #coerce" do
      x = mock("x")
      y = mock("y")
      result = mock("result")

      y.should_receive(:coerce).and_return([x, y])
      x.should_receive(:div).with(y).and_return(result)

      @bignum.div(y).should == result
    end

    it "means (x / y).floor" do
      @bignum.div(2).should == (@bignum / 2).floor
      @bignum.div(-2).should == (@bignum / -2).floor

      @bignum.div(@bignum+1).should == (@bignum / (@bignum+1)).floor
      @bignum.div(-(@bignum+1)).should == (@bignum / -(@bignum+1)).floor

      @bignum.div(2.0).should == (@bignum / 2.0).floor
      @bignum.div(100.0).should == (@bignum / 100.0).floor
    end

    it "looses precision if passed Float argument" do
      @bignum.div(1).should_not == @bignum.div(1.0)
      @bignum.div(4).should_not == @bignum.div(4.0)
      @bignum.div(21).should_not == @bignum.div(21.0)
    end

    it "raises a TypeError when given a non-numeric" do
      -> { @bignum.div(mock("10")) }.should raise_error(TypeError)
      -> { @bignum.div("2") }.should raise_error(TypeError)
      -> { @bignum.div(:symbol) }.should raise_error(TypeError)
    end

    it "returns a result of integer division of self by a float argument" do
      @bignum.div(4294967295.5).should eql(4294967296)
      not_supported_on :opal do
        @bignum.div(4294967295.0).should eql(4294967297)
        @bignum.div(bignum_value(88).to_f).should eql(1)
        @bignum.div((-bignum_value(88)).to_f).should eql(-1)
      end
    end

    # #5490
    it "raises ZeroDivisionError if the argument is 0 and is a Float" do
      -> { @bignum.div(0.0) }.should raise_error(ZeroDivisionError)
      -> { @bignum.div(-0.0) }.should raise_error(ZeroDivisionError)
    end

    it "raises ZeroDivisionError if the argument is 0 and is not a Float" do
      -> { @bignum.div(0) }.should raise_error(ZeroDivisionError)
      -> { @bignum.div(-0) }.should raise_error(ZeroDivisionError)
    end
  end
end
