require_relative '../../spec_helper'

describe "Integer#bit_length" do
  context "fixnum" do
    it "returns the position of the leftmost bit of a positive number" do
      0.bit_length.should == 0
      1.bit_length.should == 1
      2.bit_length.should == 2
      3.bit_length.should == 2
      4.bit_length.should == 3
      n = fixnum_max.bit_length
      fixnum_max[n].should == 0
      fixnum_max[n - 1].should == 1

      0.bit_length.should == 0
      1.bit_length.should == 1
      0xff.bit_length.should == 8
      0x100.bit_length.should == 9
      (2**12 - 1).bit_length.should == 12
      (2**12).bit_length.should == 13
      (2**12 + 1).bit_length.should == 13
    end

    it "returns the position of the leftmost 0 bit of a negative number" do
      -1.bit_length.should == 0
      -2.bit_length.should == 1
      -3.bit_length.should == 2
      -4.bit_length.should == 2
      -5.bit_length.should == 3
      n = fixnum_min.bit_length
      fixnum_min[n].should == 1
      fixnum_min[n - 1].should == 0

      (-2**12 - 1).bit_length.should == 13
      (-2**12).bit_length.should == 12
      (-2**12 + 1).bit_length.should == 12
      -0x101.bit_length.should == 9
      -0x100.bit_length.should == 8
      -0xff.bit_length.should == 8
      -2.bit_length.should == 1
      -1.bit_length.should == 0
    end
  end

  context "bignum" do
    it "returns the position of the leftmost bit of a positive number" do
      (2**1000-1).bit_length.should == 1000
      (2**1000).bit_length.should == 1001
      (2**1000+1).bit_length.should == 1001

      (2**10000-1).bit_length.should == 10000
      (2**10000).bit_length.should == 10001
      (2**10000+1).bit_length.should == 10001

      (1 << 100).bit_length.should == 101
      (1 << 100).succ.bit_length.should == 101
      (1 << 100).pred.bit_length.should == 100
      (1 << 10000).bit_length.should == 10001
    end

    it "returns the position of the leftmost 0 bit of a negative number" do
      (-2**10000-1).bit_length.should == 10001
      (-2**10000).bit_length.should == 10000
      (-2**10000+1).bit_length.should == 10000

      (-2**1000-1).bit_length.should == 1001
      (-2**1000).bit_length.should == 1000
      (-2**1000+1).bit_length.should == 1000

      ((-1 << 100)-1).bit_length.should == 101
      ((-1 << 100)-1).succ.bit_length.should == 100
      ((-1 << 100)-1).pred.bit_length.should == 101
      ((-1 << 10000)-1).bit_length.should == 10001
    end
  end
end
