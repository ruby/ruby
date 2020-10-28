require_relative 'spec_helper'

load_extension("numeric")

describe "CApiNumericSpecs" do
  before :each do
    @s = CApiNumericSpecs.new
  end

  describe "NUM2INT" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2INT(nil) }.should raise_error(TypeError)
    end

    it "converts a Float" do
      @s.NUM2INT(4.2).should == 4
    end

    it "converts a Bignum" do
      @s.NUM2INT(0x7fff_ffff).should == 0x7fff_ffff
    end

    it "converts a Fixnum" do
      @s.NUM2INT(5).should == 5
    end

    it "converts -1 to an signed number" do
      @s.NUM2INT(-1).should == -1
    end

    it "converts a negative Bignum into an signed number" do
      @s.NUM2INT(-2147442171).should == -2147442171
    end

    it "raises a RangeError if the value is more than 32bits" do
      -> { @s.NUM2INT(0xffff_ffff+1) }.should raise_error(RangeError)
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2INT(obj).should == 2
    end
  end

  describe "NUM2UINT" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2UINT(nil) }.should raise_error(TypeError)
    end

    it "converts a Float" do
      @s.NUM2UINT(4.2).should == 4
    end

    it "converts a Bignum" do
      @s.NUM2UINT(0xffff_ffff).should == 0xffff_ffff
    end

    it "converts a Fixnum" do
      @s.NUM2UINT(5).should == 5
    end

    it "converts a negative number to the complement" do
      @s.NUM2UINT(-1).should == 4294967295
    end

    it "converts a signed int value to the complement" do
      @s.NUM2UINT(-0x8000_0000).should == 2147483648
    end

    it "raises a RangeError if the value is more than 32bits" do
      -> { @s.NUM2UINT(0xffff_ffff+1) }.should raise_error(RangeError)
    end

    it "raises a RangeError if the value is less than 32bits negative" do
      -> { @s.NUM2UINT(-0x8000_0000-1) }.should raise_error(RangeError)
    end

    it "raises a RangeError if the value is more than 64bits" do
      -> do
        @s.NUM2UINT(0xffff_ffff_ffff_ffff+1)
      end.should raise_error(RangeError)
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2UINT(obj).should == 2
    end
  end

  describe "NUM2LONG" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2LONG(nil) }.should raise_error(TypeError)
    end

    it "converts a Float" do
      @s.NUM2LONG(4.2).should == 4
    end

    it "converts a Bignum" do
      @s.NUM2LONG(0x7fff_ffff).should == 0x7fff_ffff
    end

    it "converts a Fixnum" do
      @s.NUM2LONG(5).should == 5
    end

    platform_is wordsize: 32 do
      it "converts -1 to an signed number" do
        @s.NUM2LONG(-1).should == -1
      end

      it "converts a negative Bignum into an signed number" do
        @s.NUM2LONG(-2147442171).should == -2147442171
      end

      it "raises a RangeError if the value is more than 32bits" do
        -> { @s.NUM2LONG(0xffff_ffff+1) }.should raise_error(RangeError)
      end
    end

    platform_is wordsize: 64 do
      it "converts -1 to an signed number" do
        @s.NUM2LONG(-1).should == -1
      end

      it "converts a negative Bignum into an signed number" do
        @s.NUM2LONG(-9223372036854734331).should == -9223372036854734331
      end

      it "raises a RangeError if the value is more than 64bits" do
        -> do
          @s.NUM2LONG(0xffff_ffff_ffff_ffff+1)
        end.should raise_error(RangeError)
      end
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2LONG(obj).should == 2
    end
  end

  describe "NUM2SHORT" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2SHORT(nil) }.should raise_error(TypeError)
    end

    it "converts a Float" do
      @s.NUM2SHORT(4.2).should == 4
    end

    it "converts a Fixnum" do
      @s.NUM2SHORT(5).should == 5
    end

    it "converts -1 to an signed number" do
      @s.NUM2SHORT(-1).should == -1
    end

    it "raises a RangeError if the value is more than 32bits" do
      -> { @s.NUM2SHORT(0xffff_ffff+1) }.should raise_error(RangeError)
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2SHORT(obj).should == 2
    end
  end

  describe "INT2NUM" do
    it "raises a TypeError if passed nil" do
      -> { @s.INT2NUM(nil) }.should raise_error(TypeError)
    end

    it "converts a Float" do
      @s.INT2NUM(4.2).should == 4
    end

    it "raises a RangeError when passed a Bignum" do
      -> { @s.INT2NUM(bignum_value) }.should raise_error(RangeError)
    end

    it "converts a Fixnum" do
      @s.INT2NUM(5).should == 5
    end

    it "converts a negative Fixnum" do
      @s.INT2NUM(-11).should == -11
    end
  end

  describe "NUM2ULONG" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2ULONG(nil) }.should raise_error(TypeError)
    end

    it "converts a Float" do
      @s.NUM2ULONG(4.2).should == 4
    end

    it "converts a Bignum" do
      @s.NUM2ULONG(0xffff_ffff).should == 0xffff_ffff
    end

    it "converts a Fixnum" do
      @s.NUM2ULONG(5).should == 5
    end

    platform_is wordsize: 32 do
      it "converts -1 to an unsigned number" do
        @s.NUM2ULONG(-1).should == 4294967295
      end

      it "converts a negative Bignum into an unsigned number" do
        @s.NUM2ULONG(-2147442171).should == 2147525125
      end

      it "converts positive Bignums if the values is less than 64bits" do
        @s.NUM2ULONG(0xffff_ffff).should == 0xffff_ffff
        @s.NUM2ULONG(2**30).should == 2**30
        @s.NUM2ULONG(fixnum_max+1).should == fixnum_max+1
        @s.NUM2ULONG(fixnum_max).should == fixnum_max
      end

      it "raises a RangeError if the value is more than 32bits" do
        -> { @s.NUM2ULONG(0xffff_ffff+1) }.should raise_error(RangeError)
      end
    end

    platform_is wordsize: 64 do
      it "converts -1 to an unsigned number" do
        @s.NUM2ULONG(-1).should == 18446744073709551615
      end

      it "converts a negative Bignum into an unsigned number" do
        @s.NUM2ULONG(-9223372036854734331).should == 9223372036854817285
      end

      it "converts positive Bignums if the values is less than 64bits" do
        @s.NUM2ULONG(0xffff_ffff_ffff_ffff).should == 0xffff_ffff_ffff_ffff
        @s.NUM2ULONG(2**62).should == 2**62
        @s.NUM2ULONG(fixnum_max+1).should == fixnum_max+1
        @s.NUM2ULONG(fixnum_max).should == fixnum_max
      end

      it "raises a RangeError if the value is more than 64bits" do
        -> do
          @s.NUM2ULONG(0xffff_ffff_ffff_ffff+1)
        end.should raise_error(RangeError)
      end
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2ULONG(obj).should == 2
    end
  end

  describe "rb_Integer" do
    it "creates an Integer from a String" do
      i = @s.rb_Integer("8675309")
      i.should be_kind_of(Integer)
      i.should eql(8675309)
    end
  end

  describe "rb_ll2inum" do
    it "creates a Fixnum from a small signed long long" do
      i = @s.rb_ll2inum_14()
      i.should be_kind_of(Fixnum)
      i.should eql(14)
    end
  end

  describe "rb_ull2inum" do
    it "creates a Fixnum from a small unsigned long long" do
      i = @s.rb_ull2inum_14()
      i.should be_kind_of(Fixnum)
      i.should eql(14)
    end

    it "creates a positive Bignum from a negative long long" do
      i = @s.rb_ull2inum_n14()
      i.should be_kind_of(Bignum)
      i.should eql(2 ** (@s.size_of_long_long * 8) - 14)
    end
  end

  describe "rb_int2inum" do
    it "creates a Fixnum from a long" do
      i = @s.rb_int2inum_14()
      i.should be_kind_of(Fixnum)
      i.should eql(14)
    end
  end

  describe "rb_uint2inum" do
    it "creates a Fixnum from a long" do
      i = @s.rb_uint2inum_14()
      i.should be_kind_of(Fixnum)
      i.should eql(14)
    end

    it "creates a positive Bignum from a negative long" do
      i = @s.rb_uint2inum_n14()
      i.should be_kind_of(Bignum)
      i.should eql(2 ** (@s.size_of_VALUE * 8) - 14)
    end
  end

  describe "NUM2DBL" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2DBL(nil) }.should raise_error(TypeError)
    end

    it "raises a TypeError if passed a String" do
      -> { @s.NUM2DBL("1.2") }.should raise_error(TypeError)
    end

    it "converts a Float" do
      @s.NUM2DBL(4.2).should == 4.2
    end

    it "converts a Bignum" do
      @s.NUM2DBL(2**70).should == (2**70).to_f
    end

    it "converts a Fixnum" do
      @s.NUM2DBL(5).should == 5.0
    end

    it "calls #to_f to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_f).and_return(2.0)
      @s.NUM2DBL(obj).should == 2.0
    end
  end

  describe "NUM2CHR" do
    it "returns the first character of a String" do
      @s.NUM2CHR("Abc").should == 65
    end

    it "returns the least significant byte of an Integer" do
      @s.NUM2CHR(0xa7c).should == 0x07c
    end

    it "returns the least significant byte of a Float converted to an Integer" do
      @s.NUM2CHR(0xa7c.to_f).should == 0x07c
    end

    it "raises a TypeError when passed an empty String" do
      -> { @s.NUM2CHR("") }.should raise_error(TypeError)
    end
  end

  describe "rb_num_zerodiv" do
    it "raises a RuntimeError" do
      -> { @s.rb_num_zerodiv() }.should raise_error(ZeroDivisionError, 'divided by 0')
    end
  end

  describe "rb_cmpint" do
    it "returns a Fixnum if passed one" do
      @s.rb_cmpint(1, 2).should == 1
    end

    it "uses > to check if the value is greater than 1" do
      m = mock("number")
      m.should_receive(:>).and_return(true)
      @s.rb_cmpint(m, 4).should == 1
    end

    it "uses < to check if the value is less than 1" do
      m = mock("number")
      m.should_receive(:>).and_return(false)
      m.should_receive(:<).and_return(true)
      @s.rb_cmpint(m, 4).should == -1
    end

    it "returns 0 if < and > are false" do
      m = mock("number")
      m.should_receive(:>).and_return(false)
      m.should_receive(:<).and_return(false)
      @s.rb_cmpint(m, 4).should == 0
    end

    it "raises an ArgumentError when passed nil" do
      -> {
        @s.rb_cmpint(nil, 4)
      }.should raise_error(ArgumentError)
    end
  end

  describe "rb_num_coerce_bin" do
    it "calls #coerce on the first argument" do
      obj = mock("rb_num_coerce_bin")
      obj.should_receive(:coerce).with(2).and_return([1, 2])

      @s.rb_num_coerce_bin(2, obj, :+).should == 3
    end

    it "calls the specified method on the first argument returned by #coerce" do
      obj = mock("rb_num_coerce_bin")
      obj.should_receive(:coerce).with(2).and_return([obj, 2])
      obj.should_receive(:+).with(2).and_return(3)

      @s.rb_num_coerce_bin(2, obj, :+).should == 3
    end

    it "raises a TypeError if #coerce does not return an Array" do
      obj = mock("rb_num_coerce_bin")
      obj.should_receive(:coerce).with(2).and_return(nil)

      -> { @s.rb_num_coerce_bin(2, obj, :+) }.should raise_error(TypeError)
    end
  end

  describe "rb_num_coerce_cmp" do
    it "calls #coerce on the first argument" do
      obj = mock("rb_num_coerce_cmp")
      obj.should_receive(:coerce).with(2).and_return([1, 2])

      @s.rb_num_coerce_cmp(2, obj, :<=>).should == -1
    end

    it "calls the specified method on the first argument returned by #coerce" do
      obj = mock("rb_num_coerce_cmp")
      obj.should_receive(:coerce).with(2).and_return([obj, 2])
      obj.should_receive(:<=>).with(2).and_return(-1)

      @s.rb_num_coerce_cmp(2, obj, :<=>).should == -1
    end

    it "lets the exception go through if #coerce raises an exception" do
      obj = mock("rb_num_coerce_cmp")
      obj.should_receive(:coerce).with(2).and_raise(RuntimeError.new("my error"))
      -> {
        @s.rb_num_coerce_cmp(2, obj, :<=>)
      }.should raise_error(RuntimeError, "my error")
    end

    it "returns nil if #coerce does not return an Array" do
      obj = mock("rb_num_coerce_cmp")
      obj.should_receive(:coerce).with(2).and_return(nil)

      @s.rb_num_coerce_cmp(2, obj, :<=>).should be_nil
    end
  end

  describe "rb_num_coerce_relop" do
    it "calls #coerce on the first argument" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return([1, 2])

      @s.rb_num_coerce_relop(2, obj, :<).should be_true
    end

    it "calls the specified method on the first argument returned by #coerce" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return([obj, 2])
      obj.should_receive(:<).with(2).and_return(false)

      @s.rb_num_coerce_relop(2, obj, :<).should be_false
    end

    it "raises an ArgumentError if #<op> returns nil" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return([obj, 2])
      obj.should_receive(:<).with(2).and_return(nil)

      -> { @s.rb_num_coerce_relop(2, obj, :<) }.should raise_error(ArgumentError)
    end

    it "raises an ArgumentError if #coerce does not return an Array" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return(nil)

      -> { @s.rb_num_coerce_relop(2, obj, :<) }.should raise_error(ArgumentError)
    end
  end

  describe "rb_absint_singlebit_p" do
    it "returns 1 if absolute value fits into a bit" do
      @s.rb_absint_singlebit_p(1).should == 1
      @s.rb_absint_singlebit_p(2).should == 1
      @s.rb_absint_singlebit_p(3).should == 0
      @s.rb_absint_singlebit_p(-1).should == 1
      @s.rb_absint_singlebit_p(-2).should == 1
      @s.rb_absint_singlebit_p(-3).should == 0
      @s.rb_absint_singlebit_p(bignum_value).should == 1
      @s.rb_absint_singlebit_p(bignum_value(1)).should == 0
      @s.rb_absint_singlebit_p(-bignum_value).should == 1
      @s.rb_absint_singlebit_p(-bignum_value(1)).should == 0
    end
  end
end
