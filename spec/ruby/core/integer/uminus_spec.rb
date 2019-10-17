require_relative '../../spec_helper'

describe "Integer#-@" do
  context "fixnum" do
    it "returns self as a negative value" do
      2.send(:-@).should == -2
      -2.should == -2
      -268435455.should == -268435455
      (--5).should == 5
      -8.send(:-@).should == 8
    end

    it "negates self at Fixnum/Bignum boundaries" do
      (-fixnum_max).should == (0 - fixnum_max)
      (-fixnum_max).should < 0
      (-fixnum_min).should == (0 - fixnum_min)
      (-fixnum_min).should > 0
    end
  end

  context "bignum" do
    it "returns self as a negative value" do
      bignum_value.send(:-@).should == -9223372036854775808
      (-bignum_value).send(:-@).should == 9223372036854775808

      bignum_value(921).send(:-@).should == -9223372036854776729
      (-bignum_value(921).send(:-@)).should == 9223372036854776729
    end
  end
end
