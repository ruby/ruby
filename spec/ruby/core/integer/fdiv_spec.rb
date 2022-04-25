require_relative '../../spec_helper'

describe "Integer#fdiv" do
  it "performs floating-point division between self and a fixnum" do
    8.fdiv(7).should be_close(1.14285714285714, TOLERANCE)
  end

  it "performs floating-point division between self and a bignum" do
    8.fdiv(bignum_value).should be_close(8.673617379884035e-19, TOLERANCE)
  end

  it "performs floating-point division between self bignum and a bignum" do
    num = 1000000000000000000000000000000000048148248609680896326399448564623182963452541226153892315137780403285956264146010000000000000000000000000000000000048148248609680896326399448564623182963452541226153892315137780403285956264146010000000000000000000000000000000000048148248609680896326399448564623182963452541226153892315137780403285956264146009
    den = 2000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    num.fdiv(den).should == 500.0
  end

  it "rounds to the correct value for bignums" do
    den = 9 * 10**342

    num = 1 * 10**344
    num.fdiv(den).should == 11.11111111111111

    num = 1 * 10**343
    num.fdiv(den).should == 1.1111111111111112

    num = 1 * 10**342
    num.fdiv(den).should == 0.1111111111111111

    num = 2 * 10**342
    num.fdiv(den).should == 0.2222222222222222

    num = 3 * 10**342
    num.fdiv(den).should == 0.3333333333333333

    num = 4 * 10**342
    num.fdiv(den).should == 0.4444444444444444

    num = 5 * 10**342
    num.fdiv(den).should == 0.5555555555555556

    num = 6 * 10**342
    num.fdiv(den).should == 0.6666666666666666

    num = 7 * 10**342
    num.fdiv(den).should == 0.7777777777777778

    num = 8 * 10**342
    num.fdiv(den).should == 0.8888888888888888

    num = 9 * 10**342
    num.fdiv(den).should == 1.0

    num = -5 * 10**342
    num.fdiv(den).should == -0.5555555555555556
  end

  it "performs floating-point division between self and a Float" do
    8.fdiv(9.0).should be_close(0.888888888888889, TOLERANCE)
  end

  it "returns NaN when the argument is NaN" do
    -1.fdiv(nan_value).nan?.should be_true
    1.fdiv(nan_value).nan?.should be_true
  end

  it "returns Infinity when the argument is 0" do
    1.fdiv(0).infinite?.should == 1
  end

  it "returns -Infinity when the argument is 0 and self is negative" do
    -1.fdiv(0).infinite?.should == -1
  end

  it "returns Infinity when the argument is 0.0" do
    1.fdiv(0.0).infinite?.should == 1
  end

  it "returns -Infinity when the argument is 0.0 and self is negative" do
    -1.fdiv(0.0).infinite?.should == -1
  end

  it "raises a TypeError when argument isn't numeric" do
    -> { 1.fdiv(mock('non-numeric')) }.should raise_error(TypeError)
  end

  it "raises an ArgumentError when passed multiple arguments" do
    -> { 1.fdiv(6,0.2) }.should raise_error(ArgumentError)
  end

  it "follows the coercion protocol" do
    (obj = mock('10')).should_receive(:coerce).with(1).and_return([1, 10])
    1.fdiv(obj).should == 0.1
  end
end
