require_relative '../../spec_helper'

describe "Float#==" do
  it "returns true if self has the same value as other" do
    (1.0 == 1).should == true
    (2.71828 == 1.428).should == false
    (-4.2 == 4.2).should == false
  end

  it "calls 'other == self' if coercion fails" do
    x = mock('other')
    def x.==(other)
      2.0 == other
    end

    (1.0 == x).should == false
    (2.0 == x).should == true
  end

  it "returns false if one side is NaN" do
    [1.0, 42, bignum_value].each { |n|
      (nan_value == n).should == false
      (n == nan_value).should == false
    }
  end

  it "handles positive infinity" do
    [1.0, 42, bignum_value].each { |n|
      (infinity_value == n).should == false
      (n == infinity_value).should == false
    }
  end

  it "handles negative infinity" do
    [1.0, 42, bignum_value].each { |n|
      ((-infinity_value) == n).should == false
      (n == -infinity_value).should == false
    }
  end
end
