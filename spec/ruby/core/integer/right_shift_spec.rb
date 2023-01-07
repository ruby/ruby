require_relative '../../spec_helper'

describe "Integer#>> (with n >> m)" do
  context "fixnum" do
    it "returns n shifted right m bits when n > 0, m > 0" do
      (2 >> 1).should == 1
    end

    it "returns n shifted right m bits when n < 0, m > 0" do
      (-2 >> 1).should == -1
      (-7 >> 1).should == -4
      (-42 >> 2).should == -11
    end

    it "returns n shifted left m bits when n > 0, m < 0" do
      (1 >> -1).should == 2
    end

    it "returns n shifted left m bits when n < 0, m < 0" do
      (-1 >> -1).should == -2
    end

    it "returns 0 when n == 0" do
      (0 >> 1).should == 0
    end

    it "returns n when n > 0, m == 0" do
      (1 >> 0).should == 1
    end

    it "returns n when n < 0, m == 0" do
      (-1 >> 0).should == -1
    end

    it "returns 0 when n > 0, m > 0 and n < 2**m" do
      (3 >> 2).should == 0
      (7 >> 3).should == 0
      (127 >> 7).should == 0

      # To make sure the exponent is not truncated
      (7 >> 32).should == 0
      (7 >> 64).should == 0
    end

    it "returns -1 when n < 0, m > 0 and n > -(2**m)" do
      (-3 >> 2).should == -1
      (-7 >> 3).should == -1
      (-127 >> 7).should == -1

      # To make sure the exponent is not truncated
      (-7 >> 32).should == -1
      (-7 >> 64).should == -1
    end

    it "returns a Bignum == fixnum_max * 2 when fixnum_max >> -1 and n > 0" do
      result = fixnum_max >> -1
      result.should be_an_instance_of(Integer)
      result.should == fixnum_max * 2
    end

    it "returns a Bignum == fixnum_min * 2 when fixnum_min >> -1 and n < 0" do
      result = fixnum_min >> -1
      result.should be_an_instance_of(Integer)
      result.should == fixnum_min * 2
    end

    it "calls #to_int to convert the argument to an Integer" do
      obj = mock("2")
      obj.should_receive(:to_int).and_return(2)
      (8 >> obj).should == 2

      obj = mock("to_int_bignum")
      obj.should_receive(:to_int).and_return(bignum_value)
      (8 >> obj).should == 0
    end

    it "raises a TypeError when #to_int does not return an Integer" do
      obj = mock("a string")
      obj.should_receive(:to_int).and_return("asdf")

      -> { 3 >> obj }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed nil" do
      -> { 3 >> nil }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed a String" do
      -> { 3 >> "4" }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value * 8 # 2 ** 67
    end

    it "returns n shifted right m bits when n > 0, m > 0" do
      (@bignum >> 1).should == 73786976294838206464
    end

    it "returns n shifted right m bits when n < 0, m > 0" do
      (-@bignum >> 2).should == -36893488147419103232
    end

    it "respects twos complement signed shifting" do
      # This explicit left hand value is important because it is the
      # exact bit pattern that matters, so it's important it's right
      # here to show the significance.
      #

      (-42949672980000000000000 >> 14).should == -2621440001220703125
      (-42949672980000000000001 >> 14).should == -2621440001220703126
      # Note the off by one -------------------- ^^^^^^^^^^^^^^^^^^^^
      # This is because even though we discard the lowest bit, in twos
      # complement it would influence the bits to the left of it.

      (-42949672980000000000000 >> 15).should == -1310720000610351563
      (-42949672980000000000001 >> 15).should == -1310720000610351563

      (-0xfffffffffffffffff >> 32).should == -68719476736
    end

    it "respects twos complement signed shifting for very large values" do
      giant = 42949672980000000000000000000000000000000000000000000000000000000000000000000000000000000000
      neg = -giant

      (giant >> 84).should == 2220446050284288846538547929770901490087453566957265138626098632812
      (neg >> 84).should == -2220446050284288846538547929770901490087453566957265138626098632813
    end

    it "returns n shifted left m bits when  n > 0, m < 0" do
      (@bignum >> -2).should == 590295810358705651712
    end

    it "returns n shifted left m bits when  n < 0, m < 0" do
      (-@bignum >> -3).should == -1180591620717411303424
    end

    it "returns n when n > 0, m == 0" do
      (@bignum >> 0).should == @bignum
    end

    it "returns n when n < 0, m == 0" do
      (-@bignum >> 0).should == -@bignum
    end

    it "returns 0 when m > 0 and m == p where 2**p > n >= 2**(p-1)" do
      (@bignum >> 68).should == 0
    end

    it "returns a Fixnum == fixnum_max when (fixnum_max * 2) >> 1 and n > 0" do
      result = (fixnum_max * 2) >> 1
      result.should be_an_instance_of(Integer)
      result.should == fixnum_max
    end

    it "returns a Fixnum == fixnum_min when (fixnum_min * 2) >> 1 and n < 0" do
      result = (fixnum_min * 2) >> 1
      result.should be_an_instance_of(Integer)
      result.should == fixnum_min
    end

    it "calls #to_int to convert the argument to an Integer" do
      obj = mock("2")
      obj.should_receive(:to_int).and_return(2)

      (@bignum >> obj).should == 36893488147419103232
    end

    it "raises a TypeError when #to_int does not return an Integer" do
      obj = mock("a string")
      obj.should_receive(:to_int).and_return("asdf")

      -> { @bignum >> obj }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed nil" do
      -> { @bignum >> nil }.should raise_error(TypeError)
    end

    it "raises a TypeError when passed a String" do
      -> { @bignum >> "4" }.should raise_error(TypeError)
    end
  end

  context "when m is a bignum or larger than int" do
    it "returns -1 when m > 0 and n < 0" do
      (-1 >> bignum_value).should == -1
      (-1 >> (2**40)).should == -1

      (-bignum_value >> bignum_value).should == -1
      (-bignum_value >> (2**40)).should == -1
    end

    it "returns 0 when m > 0 and n >= 0" do
      (0 >> bignum_value).should == 0
      (1 >> bignum_value).should == 0
      (bignum_value >> bignum_value).should == 0

      (0 >> (2**40)).should == 0
      (1 >> (2**40)).should == 0
      (bignum_value >> (2**40)).should == 0
    end

    ruby_bug "#18517", ""..."3.2" do
      it "returns 0 when m < 0 long and n == 0" do
        (0 >> -(2**40)).should == 0
      end
    end

    it "returns 0 when m < 0 bignum and n == 0" do
      (0 >> -bignum_value).should == 0
    end

    it "raises RangeError when m < 0 and n != 0" do
      # https://bugs.ruby-lang.org/issues/18518#note-9
      limit = RUBY_ENGINE == 'ruby' ? 2**67 : 2**32

      coerce_long = mock("long")
      coerce_long.stub!(:to_int).and_return(-limit)
      coerce_bignum = mock("bignum")
      coerce_bignum.stub!(:to_int).and_return(-bignum_value)
      exps = [-limit, coerce_long]
      exps << -bignum_value << coerce_bignum if bignum_value >= limit

      exps.each { |exp|
        -> { (1 >> exp) }.should raise_error(RangeError, 'shift width too big')
        -> { (-1 >> exp) }.should raise_error(RangeError, 'shift width too big')
        -> { (bignum_value >> exp) }.should raise_error(RangeError, 'shift width too big')
        -> { (-bignum_value >> exp) }.should raise_error(RangeError, 'shift width too big')
      }
    end
  end
end
