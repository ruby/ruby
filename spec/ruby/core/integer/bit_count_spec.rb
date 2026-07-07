require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "Integer#bit_count" do
    it "returns the number of set bits in the binary representation" do
      0.bit_count.should == 0
      1.bit_count.should == 1
      2.bit_count.should == 1
      3.bit_count.should == 2
      7.bit_count.should == 3
      0b10101.bit_count.should == 3
      0xff.bit_count.should == 8
      0x100.bit_count.should == 1
      fixnum_max.bit_count.should == fixnum_max.to_s(2).count("1")

      (2**1000).bit_count.should == 1
      (2**1000 - 1).bit_count.should == 1000
      (2**1000 + 2**500).bit_count.should == 2
      (2**64 - 1).bit_count.should == 64
      (2**10000 - 1).bit_count.should == 10000
    end

    it "raises an ArgumentError for a negative number" do
      -> { -1.bit_count }.should raise_error(ArgumentError)
      -> { -19.bit_count }.should raise_error(ArgumentError)
      -> { fixnum_min.bit_count }.should raise_error(ArgumentError)
      -> { (-2**1000).bit_count }.should raise_error(ArgumentError)
      -> { (-2**1000 - 1).bit_count }.should raise_error(ArgumentError)
    end
  end
end
