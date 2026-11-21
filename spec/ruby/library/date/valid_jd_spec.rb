require_relative '../../spec_helper'
require 'date'

describe "Date.valid_jd?" do
  it "returns true if passed a number value" do
    Date.valid_jd?(-100).should == true
    Date.valid_jd?(100.0).should == true
    Date.valid_jd?(2**100).should == true
    Date.valid_jd?(Rational(1,2)).should == true
  end

  it "returns false if passed nil" do
    Date.valid_jd?(nil).should == false
  end

  it "returns false if passed symbol" do
    Date.valid_jd?(:number).should == false
  end

  it "returns false if passed false" do
    Date.valid_jd?(false).should == false
  end
end
