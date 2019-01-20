require_relative 'spec_helper'

load_extension("fixnum")

describe "CApiFixnumSpecs" do
  before :each do
    @s = CApiFixnumSpecs.new
  end

  describe "FIX2INT" do
    max_int = (1 << 31) - 1
    min_int = -(1 << 31)

    it "converts a Fixnum to a native int" do
      @s.FIX2INT(42).should == 42
      @s.FIX2INT(-14).should == -14
      @s.FIX2INT(-1).should == -1
      @s.FIX2INT(1).should == 1
    end

    guard -> { fixnum_min <= min_int and max_int <= fixnum_max } do
      it "converts a Fixnum representing the minimum and maximum native int" do
        @s.FIX2INT(max_int).should == max_int
        @s.FIX2INT(min_int).should == min_int
      end
    end

    platform_is wordsize: 64 do # sizeof(long) > sizeof(int)
      it "raises a TypeError if passed nil" do
        lambda { @s.FIX2INT(nil) }.should raise_error(TypeError)
      end

      it "converts a Float" do
        @s.FIX2INT(25.4567).should == 25
      end

      it "converts a negative Bignum into an signed number" do
        @s.FIX2INT(-2147442171).should == -2147442171
      end

      it "raises a RangeError if the value does not fit a native int" do
        lambda { @s.FIX2INT(0x7fff_ffff+1) }.should raise_error(RangeError)
        lambda { @s.FIX2INT(-(1 << 31) - 1) }.should raise_error(RangeError)
      end

      it "raises a RangeError if the value is more than 32bits" do
        lambda { @s.FIX2INT(0xffff_ffff+1) }.should raise_error(RangeError)
      end

      it "raises a RangeError if the value is more than 64bits" do
        lambda { @s.FIX2INT(0xffff_ffff_ffff_ffff+1) }.should raise_error(RangeError)
      end

      it "calls #to_int to coerce the value" do
        obj = mock("number")
        obj.should_receive(:to_int).and_return(2)
        @s.FIX2INT(obj).should == 2
      end
    end
  end

  describe "FIX2UINT" do
    max_uint = (1 << 32) - 1

    it "converts a Fixnum" do
      @s.FIX2UINT(0).should == 0
      @s.FIX2UINT(1).should == 1
      @s.FIX2UINT(42).should == 42
    end

    guard -> { max_uint <= fixnum_max } do
      it "converts a Fixnum representing the maximum native uint" do
        @s.FIX2UINT(max_uint).should == max_uint
      end
    end

    platform_is wordsize: 64 do # sizeof(long) > sizeof(int)
      it "raises a TypeError if passed nil" do
        lambda { @s.FIX2UINT(nil) }.should raise_error(TypeError)
      end

      it "converts a Float" do
        @s.FIX2UINT(25.4567).should == 25
      end

      it "raises a RangeError if the value does not fit a native uint" do
        # Interestingly, on MRI FIX2UINT(-1) is allowed
        lambda { @s.FIX2UINT(0xffff_ffff+1) }.should raise_error(RangeError)
        lambda { @s.FIX2UINT(-(1 << 31) - 1) }.should raise_error(RangeError)
      end

      it "raises a RangeError if the value is more than 32bits" do
        lambda { @s.FIX2UINT(0xffff_ffff+1) }.should raise_error(RangeError)
      end

      it "raises a RangeError if the value is more than 64bits" do
        lambda { @s.FIX2UINT(0xffff_ffff_ffff_ffff+1) }.should raise_error(RangeError)
      end
    end
  end
end
