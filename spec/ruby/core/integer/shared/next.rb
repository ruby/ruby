describe :integer_next, shared: true do
  it "returns the next larger positive Integer" do
    2.send(@method).should == 3
  end

  it "returns the next larger negative Integer" do
    (-2).send(@method).should == -1
  end

  it "returns the next larger positive Integer" do
    bignum_value.send(@method).should == bignum_value(1)
  end

  it "returns the next larger negative Integer" do
    (-bignum_value(1)).send(@method).should == -bignum_value
  end

  it "overflows an Integer to an Integer" do
    fixnum_max.send(@method).should == fixnum_max + 1
  end

  it "underflows an Integer to an Integer" do
    (fixnum_min - 1).send(@method).should == fixnum_min
  end
end
