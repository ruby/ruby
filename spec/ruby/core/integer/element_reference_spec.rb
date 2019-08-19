require_relative '../../spec_helper'

describe "Integer#[]" do
  context "fixnum" do
    it "behaves like (n >> b) & 1" do
      0b101[1].should == 0
      0b101[2].should == 1
    end

    it "returns 1 if the nth bit is set" do
      15[1].should == 1
    end

    it "returns 1 if the nth bit is set (in two's-complement representation)" do
      (-1)[1].should == 1
    end

    it "returns 0 if the nth bit is not set" do
      8[2].should == 0
    end

    it "returns 0 if the nth bit is not set (in two's-complement representation)" do
      (-2)[0].should == 0
    end

    it "returns 0 if the nth bit is greater than the most significant bit" do
      2[3].should == 0
    end

    it "returns 1 if self is negative and the nth bit is greater than the most significant bit" do
      (-1)[3].should == 1
    end

    it "returns 0 when passed a negative argument" do
      3[-1].should == 0
      (-1)[-1].should == 0
    end

    it "calls #to_int to convert the argument to an Integer and returns 1 if the nth bit is set" do
      obj = mock('1')
      obj.should_receive(:to_int).and_return(1)

      2[obj].should == 1
    end

    it "calls #to_int to convert the argument to an Integer and returns 0 if the nth bit is set" do
      obj = mock('0')
      obj.should_receive(:to_int).and_return(0)

      2[obj].should == 0
    end

    it "accepts a Float argument and returns 0 if the bit at the truncated value is not set" do
      13[1.3].should == 0
    end

    it "accepts a Float argument and returns 1 if the bit at the truncated value is set" do
      13[2.1].should == 1
    end

    it "raises a TypeError when passed a String" do
      lambda { 3["3"] }.should raise_error(TypeError)
    end

    it "raises a TypeError when #to_int does not return an Integer" do
      obj = mock('asdf')
      obj.should_receive(:to_int).and_return("asdf")
      lambda { 3[obj] }.should raise_error(TypeError)
    end

    it "calls #to_int to coerce a String to a Bignum and returns 0" do
      obj = mock('bignum value')
      obj.should_receive(:to_int).and_return(bignum_value)

      3[obj].should == 0
    end

    it "returns 0 when passed a Float in the range of a Bignum" do
      3[bignum_value.to_f].should == 0
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(4996)
    end

    it "returns the nth bit in the binary representation of self" do
      @bignum[2].should == 1
      @bignum[9.2].should == 1
      @bignum[21].should == 0
      @bignum[0xffffffff].should == 0
      @bignum[-0xffffffff].should == 0
    end

    it "tries to convert the given argument to an Integer using #to_int" do
      @bignum[1.3].should == @bignum[1]

      (obj = mock('2')).should_receive(:to_int).at_least(1).and_return(2)
      @bignum[obj].should == 1
    end

    it "raises a TypeError when the given argument can't be converted to Integer" do
      obj = mock('asdf')
      lambda { @bignum[obj] }.should raise_error(TypeError)

      obj.should_receive(:to_int).and_return("asdf")
      lambda { @bignum[obj] }.should raise_error(TypeError)
    end
  end
end
