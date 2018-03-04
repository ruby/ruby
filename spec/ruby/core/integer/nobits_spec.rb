require_relative '../../spec_helper'

ruby_version_is '2.5' do
  describe "Integer#nobits?" do
    it "returns true iff all no bits of the argument are set in the receiver" do
      42.nobits?(42).should == false
      0b1010_1010.nobits?(0b1000_0010).should == false
      0b1010_1010.nobits?(0b1000_0001).should == false
      0b0100_0101.nobits?(0b1010_1010).should == true
      different_bignum = (2 * bignum_value) & (~bignum_value)
      (0b1010_1010 | different_bignum).nobits?(0b1000_0010 | bignum_value).should == false
      (0b1010_1010 | different_bignum).nobits?(0b1000_0001 | bignum_value).should == false
      (0b0100_0101 | different_bignum).nobits?(0b1010_1010 | bignum_value).should == true
    end

    it "handles negative values using two's complement notation" do
      (~0b1101).nobits?(0b1101).should == true
      (-42).nobits?(-42).should == false
      (~0b1101).nobits?(~0b10).should == false
      (~(0b1101 | bignum_value)).nobits?(~(0b10 | bignum_value)).should == false
    end

    it "coerces the rhs using to_int" do
      obj = mock("the int 0b10")
      obj.should_receive(:to_int).and_return(0b10)
      0b110.nobits?(obj).should == false
    end

    it "raises a TypeError when given a non-Integer" do
      lambda {
        (obj = mock('10')).should_receive(:coerce).any_number_of_times.and_return([42,10])
        13.nobits?(obj)
      }.should raise_error(TypeError)
      lambda { 13.nobits?("10")    }.should raise_error(TypeError)
      lambda { 13.nobits?(:symbol) }.should raise_error(TypeError)
    end
  end
end
