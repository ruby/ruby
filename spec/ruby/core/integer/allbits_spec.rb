require File.expand_path('../../../spec_helper', __FILE__)

describe "Integer#allbits?" do
  it "returns true iff all the bits of the argument are set in the receiver" do
    42.allbits?(42).should == true
    0b1010_1010.allbits?(0b1000_0010).should == true
    0b1010_1010.allbits?(0b1000_0001).should == false
    0b1000_0010.allbits?(0b1010_1010).should == false
    (0b1010_1010 | bignum_value).allbits?(0b1000_0010 | bignum_value).should == true
    (0b1010_1010 | bignum_value).allbits?(0b1000_0001 | bignum_value).should == false
    (0b1000_0010 | bignum_value).allbits?(0b1010_1010 | bignum_value).should == false
  end

  it "handles negative values using two's complement notation" do
    (~0b1).allbits?(42).should == true
    (-42).allbits?(-42).should == true
    (~0b1010_1010).allbits?(~0b1110_1011).should == true
    (~0b1010_1010).allbits?(~0b1000_0010).should == false
    (~(0b1010_1010 | bignum_value)).allbits?(~(0b1110_1011 | bignum_value)).should == true
    (~(0b1010_1010 | bignum_value)).allbits?(~(0b1000_0010 | bignum_value)).should == false
  end

  it "coerces the rhs using to_int" do
    obj = mock("the int 0b10")
    obj.should_receive(:to_int).and_return(0b10)
    0b110.allbits?(obj).should == true
  end

  it "raises a TypeError when given a non-Integer" do
    lambda {
      (obj = mock('10')).should_receive(:coerce).any_number_of_times.and_return([42,10])
      13.allbits?(obj)
    }.should raise_error(TypeError)
    lambda { 13.allbits?("10")    }.should raise_error(TypeError)
    lambda { 13.allbits?(:symbol) }.should raise_error(TypeError)
  end
end
