require_relative '../../spec_helper'

describe "Integer#digits" do
  it "returns an array of place values in base-10 by default" do
    12345.digits.should == [5,4,3,2,1]
  end

  it "returns digits by place value of a given radix" do
    12345.digits(7).should == [4,6,6,0,5]
  end

  it "converts the radix with #to_int" do
    12345.digits(mock_int(2)).should == [1, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1]
  end

  it "returns [0] when called on 0, regardless of base" do
    0.digits.should == [0]
    0.digits(7).should == [0]
  end

  it "raises ArgumentError when calling with a radix less than 2" do
    lambda { 12345.digits(1) }.should raise_error(ArgumentError)
  end

  it "raises ArgumentError when calling with a negative radix" do
    lambda { 12345.digits(-2) }.should raise_error(ArgumentError)
  end

  it "raises Math::DomainError when calling digits on a negative number" do
    lambda { -12345.digits(7) }.should raise_error(Math::DomainError)
  end
end
