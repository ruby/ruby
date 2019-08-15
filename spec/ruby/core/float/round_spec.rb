require_relative '../../spec_helper'

describe "Float#round" do
  it "returns the nearest Integer" do
    5.5.round.should == 6
    0.4.round.should == 0
    0.6.round.should == 1
    -1.4.round.should == -1
    -2.8.round.should == -3
    0.0.round.should == 0
  end

  it "returns the nearest Integer for Float near the limit" do
    0.49999999999999994.round.should == 0
    -0.49999999999999994.round.should == 0
  end

  it "raises FloatDomainError for exceptional values" do
    -> { (+infinity_value).round }.should raise_error(FloatDomainError)
    -> { (-infinity_value).round }.should raise_error(FloatDomainError)
    -> { nan_value.round }.should raise_error(FloatDomainError)
  end

  it "rounds self to an optionally given precision" do
    5.5.round(0).should eql(6)
    5.7.round(1).should eql(5.7)
    1.2345678.round(2).should == 1.23
    123456.78.round(-2).should eql(123500) # rounded up
    -123456.78.round(-2).should eql(-123500)
    12.345678.round(3.999).should == 12.346
  end

  it "returns zero when passed a negative argument with magnitude greater than magnitude of the whole number portion of the Float" do
    0.8346268.round(-1).should eql(0)
  end

  it "raises a TypeError when its argument can not be converted to an Integer" do
    -> { 1.0.round("4") }.should raise_error(TypeError)
    -> { 1.0.round(nil) }.should raise_error(TypeError)
  end

  it "raises FloatDomainError for exceptional values when passed a non-positive precision" do
    -> { Float::INFINITY.round( 0) }.should raise_error(FloatDomainError)
    -> { Float::INFINITY.round(-2) }.should raise_error(FloatDomainError)
    -> { (-Float::INFINITY).round( 0) }.should raise_error(FloatDomainError)
    -> { (-Float::INFINITY).round(-2) }.should raise_error(FloatDomainError)
  end

  it "raises RangeError for NAN when passed a non-positive precision" do
    -> { Float::NAN.round(0) }.should raise_error(RangeError)
    -> { Float::NAN.round(-2) }.should raise_error(RangeError)
  end

  it "returns self for exceptional values when passed a non-negative precision" do
    Float::INFINITY.round(2).should == Float::INFINITY
    (-Float::INFINITY).round(2).should == -Float::INFINITY
    Float::NAN.round(2).should be_nan
  end

  # redmine:5227
  it "works for corner cases" do
    42.0.round(308).should eql(42.0)
    1.0e307.round(2).should eql(1.0e307)
  end

  # redmine:5271
  it "returns rounded values for big argument" do
    0.42.round(2.0**30).should == 0.42
  end

  it "returns big values rounded to nearest" do
    +2.5e20.round(-20).should   eql( +3 * 10 ** 20  )
    -2.5e20.round(-20).should   eql( -3 * 10 ** 20  )
  end

  # redmine #5272
  it "returns rounded values for big values" do
    +2.4e20.round(-20).should   eql( +2 * 10 ** 20  )
    -2.4e20.round(-20).should   eql( -2 * 10 ** 20  )
    +2.5e200.round(-200).should eql( +3 * 10 ** 200 )
    +2.4e200.round(-200).should eql( +2 * 10 ** 200 )
    -2.5e200.round(-200).should eql( -3 * 10 ** 200 )
    -2.4e200.round(-200).should eql( -2 * 10 ** 200 )
  end

  it "returns different rounded values depending on the half option" do
    2.5.round(half: nil).should      eql(3)
    2.5.round(half: :up).should      eql(3)
    2.5.round(half: :down).should    eql(2)
    2.5.round(half: :even).should    eql(2)
    3.5.round(half: nil).should      eql(4)
    3.5.round(half: :up).should      eql(4)
    3.5.round(half: :down).should    eql(3)
    3.5.round(half: :even).should    eql(4)
    (-2.5).round(half: nil).should   eql(-3)
    (-2.5).round(half: :up).should   eql(-3)
    (-2.5).round(half: :down).should eql(-2)
    (-2.5).round(half: :even).should eql(-2)
  end

  it "rounds self to an optionally given precision with a half option" do
    5.55.round(1, half: nil).should eql(5.6)
    5.55.round(1, half: :up).should eql(5.6)
    5.55.round(1, half: :down).should eql(5.5)
    5.55.round(1, half: :even).should eql(5.6)
  end

  it "raises FloatDomainError for exceptional values with a half option" do
    -> { (+infinity_value).round(half: :up) }.should raise_error(FloatDomainError)
    -> { (-infinity_value).round(half: :down) }.should raise_error(FloatDomainError)
    -> { nan_value.round(half: :even) }.should raise_error(FloatDomainError)
  end

  it "raise for a non-existent round mode" do
    -> { 14.2.round(half: :nonsense) }.should raise_error(ArgumentError, "invalid rounding mode: nonsense")
  end
end
