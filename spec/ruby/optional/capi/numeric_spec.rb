require_relative 'spec_helper'

load_extension("numeric")

describe "CApiNumericSpecs" do
  uint_max = RbConfig::LIMITS["UINT_MAX"]
  int_max = RbConfig::LIMITS["INT_MAX"]
  int_min = RbConfig::LIMITS["INT_MIN"]
  ulong_max = RbConfig::LIMITS["ULONG_MAX"]
  long_max = RbConfig::LIMITS["LONG_MAX"]
  long_min = RbConfig::LIMITS["LONG_MIN"]
  ushrt_max = RbConfig::LIMITS["USHRT_MAX"]
  shrt_max = RbConfig::LIMITS["SHRT_MAX"]
  shrt_min = RbConfig::LIMITS["SHRT_MIN"]

  before :each do
    @s = CApiNumericSpecs.new
  end

  describe "NUM2INT" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2INT(nil) }.should.raise(TypeError)
    end

    it "converts a Float" do
      @s.NUM2INT(4.2).should == 4
    end

    it "converts a Fixnum" do
      @s.NUM2INT(5).should == 5
    end

    it "converts -1 to an signed number" do
      @s.NUM2INT(-1).should == -1
    end

    guard -> { int_max > fixnum_max } do
      it "converts a Bignum" do
        @s.NUM2INT(int_max).should == int_max
      end
    end

    guard -> { int_min < fixnum_min } do
      it "converts a negative Bignum into an signed numbe r" do
        @s.NUM2INT(fixnum_min-1).should == fixnum_min-1
      end
    end

    it "raises a RangeError if the value is more than INT_MAX" do
      -> { @s.NUM2INT(int_max+1) }.should.raise(RangeError)
    end

    it "raises a RangeError if the value is less than INT_MIN" do
      -> { @s.NUM2INT(int_min-1) }.should.raise(RangeError)
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2INT(obj).should == 2
    end
  end

  describe "NUM2UINT" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2UINT(nil) }.should.raise(TypeError)
    end

    it "converts a Float" do
      @s.NUM2UINT(4.2).should == 4
    end

    it "converts a Fixnum" do
      @s.NUM2UINT(5).should == 5
    end

    it "converts a negative number to the complement" do
      @s.NUM2UINT(-1).should == uint_max
    end

    it "converts a signed int value to the complement" do
      @s.NUM2UINT(int_min).should == int_max + 1
    end

    guard -> { uint_max > fixnum_max } do
      it "converts a Bignum" do
        @s.NUM2UINT(uint_max).should == uint_max
      end
    end

    it "raises a RangeError if the value is more than UINT_MAX" do
      -> { @s.NUM2UINT(uint_max+1) }.should.raise(RangeError)
    end

    it "raises a RangeError if the value is less than INT_MIN" do
      -> { @s.NUM2UINT(int_min-1) }.should.raise(RangeError)
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2UINT(obj).should == 2
    end
  end

  describe "NUM2LONG" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2LONG(nil) }.should.raise(TypeError)
    end

    it "converts a Float" do
      @s.NUM2LONG(4.2).should == 4
    end

    it "converts a Fixnum" do
      @s.NUM2LONG(5).should == 5
    end

    it "converts -1 to an signed number" do
      @s.NUM2LONG(-1).should == -1
    end

    it "converts a positive number into an signed number" do
      @s.NUM2LONG(long_max).should == long_max
    end

    it "converts a negative number into an signed number" do
      @s.NUM2LONG(long_min).should == long_min
    end

    it "raises a RangeError if the value is more than LONG_MAX" do
      -> { @s.NUM2LONG(long_max+1) }.should.raise(RangeError)
    end

    it "raises a RangeError if the value is less than LONG_MIN" do
      -> { @s.NUM2LONG(long_min-1) }.should.raise(RangeError)
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2LONG(obj).should == 2
    end
  end

  describe "NUM2SHORT" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2SHORT(nil) }.should.raise(TypeError)
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

    it "converts a positive number into an signed number" do
      @s.NUM2SHORT(shrt_max).should == shrt_max
    end

    it "converts a negative number into an signed number" do
      @s.NUM2SHORT(shrt_min).should == shrt_min
    end

    it "raises a RangeError if the value is more than SHRT_MAX" do
      -> { @s.NUM2SHORT(shrt_max+1) }.should.raise(RangeError)
    end

    it "raises a RangeError if the value is less than SHRT_MIN" do
      -> { @s.NUM2SHORT(shrt_min-1) }.should.raise(RangeError)
    end

    it "calls #to_int to coerce the value" do
      obj = mock("number")
      obj.should_receive(:to_int).and_return(2)
      @s.NUM2SHORT(obj).should == 2
    end
  end

  describe "INT2NUM" do
    it "raises a TypeError if passed nil" do
      -> { @s.INT2NUM(nil) }.should.raise(TypeError)
    end

    it "converts a Float" do
      @s.INT2NUM(4.2).should == 4
    end

    it "converts a Fixnum" do
      @s.INT2NUM(5).should == 5
    end

    it "converts a negative Fixnum" do
      @s.INT2NUM(-11).should == -11
    end

    it "converts a positive number into an signed number" do
      @s.NUM2INT(int_max).should == int_max
    end

    it "converts a negative number into an signed number" do
      @s.NUM2INT(int_min).should == int_min
    end

    it "raises a RangeError if the value is more than INT_MAX" do
      -> { @s.NUM2INT(int_max+1) }.should.raise(RangeError)
    end

    it "raises a RangeError if the value is less than INT_MIN" do
      -> { @s.NUM2INT(int_min-1) }.should.raise(RangeError)
    end
  end

  describe "NUM2ULONG" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2ULONG(nil) }.should.raise(TypeError)
    end

    it "converts a Float" do
      @s.NUM2ULONG(4.2).should == 4
    end

    it "raises a RangeError if passed a Float out of range" do
      -> { @s.NUM2ULONG(Float::NAN) }.should.raise(RangeError, "float NaN out of range of integer")
      -> { @s.NUM2ULONG(Float::INFINITY) }.should.raise(RangeError, "float Inf out of range of integer")
      -> { @s.NUM2ULONG(-Float::INFINITY) }.should.raise(RangeError, "float -Inf out of range of integer")
      -> { @s.NUM2ULONG(2.0**64) }.should.raise(RangeError, "float 1.844674407e+19 out of range of integer")
    end

    it "converts a Fixnum" do
      @s.NUM2ULONG(5).should == 5
    end


    it "converts a negative number to the complement" do
      @s.NUM2ULONG(-1).should == ulong_max
      @s.NUM2ULONG(long_min).should == long_max + 1
    end

    it "converts a ULONG_MAX" do
      @s.NUM2ULONG(ulong_max).should == ulong_max
    end

    it "raises a RangeError if the value is more than ULONG_MAX" do
      -> { @s.NUM2ULONG(ulong_max+1) }.should.raise(RangeError)
    end

    it "raises a RangeError if the value is less than LONG_MIN" do
      -> { @s.NUM2ULONG(long_min-1) }.should.raise(RangeError)
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
      i.should == 8675309
    end
  end

  describe "rb_ll2inum" do
    it "creates a Fixnum from a small signed long long" do
      i = @s.rb_ll2inum_14()
      i.should == 14
    end
  end

  describe "rb_ull2inum" do
    it "creates a Fixnum from a small unsigned long long" do
      i = @s.rb_ull2inum_14()
      i.should == 14
    end

    it "creates a positive Bignum from a negative long long" do
      i = @s.rb_ull2inum_n14()
      i.should == (2 ** (@s.size_of_long_long * 8) - 14)
    end
  end

  describe "rb_int2inum" do
    it "creates a Fixnum from a long" do
      i = @s.rb_int2inum_14()
      i.should == 14
    end
  end

  describe "rb_uint2inum" do
    it "creates a Fixnum from a long" do
      i = @s.rb_uint2inum_14()
      i.should == 14
    end

    it "creates a positive Bignum from a negative long" do
      i = @s.rb_uint2inum_n14()
      i.should == (2 ** (@s.size_of_VALUE * 8) - 14)
    end
  end

  describe "NUM2DBL" do
    it "raises a TypeError if passed nil" do
      -> { @s.NUM2DBL(nil) }.should.raise(TypeError)
    end

    it "raises a TypeError if passed a String" do
      -> { @s.NUM2DBL("1.2") }.should.raise(TypeError)
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
      -> { @s.NUM2CHR("") }.should.raise(TypeError)
    end
  end

  describe "rb_num_zerodiv" do
    it "raises a RuntimeError" do
      -> { @s.rb_num_zerodiv() }.should.raise(ZeroDivisionError, 'divided by 0')
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
      }.should.raise(ArgumentError)
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

      -> { @s.rb_num_coerce_bin(2, obj, :+) }.should.raise(TypeError)
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
      }.should.raise(RuntimeError, "my error")
    end

    it "returns nil if #coerce does not return an Array" do
      obj = mock("rb_num_coerce_cmp")
      obj.should_receive(:coerce).with(2).and_return(nil)

      @s.rb_num_coerce_cmp(2, obj, :<=>).should == nil
    end
  end

  describe "rb_num_coerce_relop" do
    it "calls #coerce on the first argument" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return([1, 2])

      @s.rb_num_coerce_relop(2, obj, :<).should == true
    end

    it "calls the specified method on the first argument returned by #coerce" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return([obj, 2])
      obj.should_receive(:<).with(2).and_return(false)

      @s.rb_num_coerce_relop(2, obj, :<).should == false
    end

    it "raises an ArgumentError if #<op> returns nil" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return([obj, 2])
      obj.should_receive(:<).with(2).and_return(nil)

      -> { @s.rb_num_coerce_relop(2, obj, :<) }.should.raise(ArgumentError)
    end

    it "raises an ArgumentError if #coerce does not return an Array" do
      obj = mock("rb_num_coerce_relop")
      obj.should_receive(:coerce).with(2).and_return(nil)

      -> { @s.rb_num_coerce_relop(2, obj, :<) }.should.raise(ArgumentError)
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
