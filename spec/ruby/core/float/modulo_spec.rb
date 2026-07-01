require_relative '../../spec_helper'

describe "Float#%" do
  it "returns self modulo other" do
    (6543.21 % 137).should be_close(104.21, TOLERANCE)
    (5667.19 % bignum_value).should be_close(5667.19, TOLERANCE)
    (6543.21 % 137.24).should be_close(92.9299999999996, TOLERANCE)

    (-1.0 % 1).should == 0
  end

  it "returns self when modulus is +Infinity" do
    (4.2 % Float::INFINITY).should == 4.2
  end

  it "returns -Infinity when modulus is -Infinity" do
    (4.2 % -Float::INFINITY).should == -Float::INFINITY
  end

  it "returns NaN when called on NaN or Infinities" do
    (Float::NAN % 42).should.nan?
    (Float::INFINITY % 42).should.nan?
    (-Float::INFINITY % 42).should.nan?
  end

  it "returns NaN when modulus is NaN" do
    (4.2 % Float::NAN).should.nan?
  end

  it "returns -0.0 when called on -0.0 with a non zero modulus" do
    r = -0.0 % 42
    r.should == 0
    (1/r).should < 0

    r = -0.0 % Float::INFINITY
    r.should == 0
    (1/r).should < 0
  end

  it "tries to coerce the modulus" do
    obj = mock("modulus")
    obj.should_receive(:coerce).with(1.25).and_return([1.25, 0.5])
    (1.25 % obj).should == 0.25
  end

  it "raises a ZeroDivisionError if other is zero" do
    -> { 1.0 % 0 }.should.raise(ZeroDivisionError)
    -> { 1.0 % 0.0 }.should.raise(ZeroDivisionError)
  end
end

describe "Float#modulo" do
  it "is an alias of Float#%" do
    Float.instance_method(:modulo).should == Float.instance_method(:%)
  end
end
