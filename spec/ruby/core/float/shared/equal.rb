describe :float_equal, shared: true do
  it "returns true if self has the same value as other" do
    1.0.send(@method, 1).should == true
    2.71828.send(@method, 1.428).should == false
    -4.2.send(@method, 4.2).should == false
  end

  it "calls 'other == self' if coercion fails" do
    x = mock('other')
    def x.==(other)
      2.0 == other
    end

    1.0.send(@method, x).should == false
    2.0.send(@method, x).should == true
  end

  it "returns false if one side is NaN" do
    [1.0, 42, bignum_value].each { |n|
      (nan_value.send(@method, n)).should == false
      (n.send(@method, nan_value)).should == false
    }
  end

  it "handles positive infinity" do
    [1.0, 42, bignum_value].each { |n|
      (infinity_value.send(@method, n)).should == false
      (n.send(@method, infinity_value)).should == false
    }
  end

  it "handles negative infinity" do
    [1.0, 42, bignum_value].each { |n|
      ((-infinity_value).send(@method, n)).should == false
      (n.send(@method, -infinity_value)).should == false
    }
  end
end
