require_relative '../../spec_helper'

describe "Integer#divmod" do
  context "fixnum" do
    it "returns an Array containing quotient and modulus obtained from dividing self by the given argument" do
      13.divmod(4).should == [3, 1]
      4.divmod(13).should == [0, 4]

      13.divmod(4.0).should == [3, 1]
      4.divmod(13.0).should == [0, 4]

      1.divmod(2.0).should == [0, 1.0]
      200.divmod(bignum_value).should == [0, 200]
    end

    it "raises a ZeroDivisionError when the given argument is 0" do
      -> { 13.divmod(0)  }.should raise_error(ZeroDivisionError)
      -> { 0.divmod(0)   }.should raise_error(ZeroDivisionError)
      -> { -10.divmod(0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a ZeroDivisionError when the given argument is 0 and a Float" do
      -> { 0.divmod(0.0)   }.should raise_error(ZeroDivisionError)
      -> { 10.divmod(0.0)  }.should raise_error(ZeroDivisionError)
      -> { -10.divmod(0.0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a TypeError when given a non-Integer" do
      -> {
        (obj = mock('10')).should_receive(:to_int).any_number_of_times.and_return(10)
        13.divmod(obj)
      }.should raise_error(TypeError)
      -> { 13.divmod("10")    }.should raise_error(TypeError)
      -> { 13.divmod(:symbol) }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(55)
    end

    # Based on MRI's test/test_integer.rb (test_divmod),
    # MRI maintains the following property:
    # if q, r = a.divmod(b) ==>
    # assert(0 < b ? (0 <= r && r < b) : (b < r && r <= 0))
    # So, r is always between 0 and b.
    it "returns an Array containing quotient and modulus obtained from dividing self by the given argument" do
      @bignum.divmod(4).should == [4611686018427387917, 3]
      @bignum.divmod(13).should == [1418980313362273205, 6]

      @bignum.divmod(4.5).should == [4099276460824344576, 2.5]

      not_supported_on :opal do
        @bignum.divmod(4.0).should == [4611686018427387904, 0.0]
        @bignum.divmod(13.0).should == [1418980313362273280, 3.0]

        @bignum.divmod(2.0).should == [9223372036854775808, 0.0]
      end

      @bignum.divmod(bignum_value).should == [1, 55]

      (-(10**50)).divmod(-(10**40 + 1)).should == [9999999999, -9999999999999999999999999999990000000001]
      (10**50).divmod(10**40 + 1).should == [9999999999, 9999999999999999999999999999990000000001]

      (-10**50).divmod(10**40 + 1).should == [-10000000000, 10000000000]
      (10**50).divmod(-(10**40 + 1)).should == [-10000000000, -10000000000]
    end

    describe "with q = floor(x/y), a = q*b + r," do
      it "returns [q,r] when a < 0, b > 0 and |a| < b" do
        a = -@bignum + 1
        b =  @bignum
        a.divmod(b).should == [-1, 1]
      end

      it "returns [q,r] when a > 0, b < 0 and a > |b|" do
        b = -@bignum + 1
        a =  @bignum
        a.divmod(b).should == [-2, -@bignum + 2]
      end

      it "returns [q,r] when a > 0, b < 0 and a < |b|" do
        a =  @bignum - 1
        b = -@bignum
        a.divmod(b).should == [-1, -1]
      end

      it "returns [q,r] when a < 0, b < 0 and |a| < |b|" do
        a = -@bignum + 1
        b = -@bignum
        a.divmod(b).should == [0, -@bignum + 1]
      end
    end

    it "raises a ZeroDivisionError when the given argument is 0" do
      -> { @bignum.divmod(0) }.should raise_error(ZeroDivisionError)
      -> { (-@bignum).divmod(0) }.should raise_error(ZeroDivisionError)
    end

    # Behaviour established as correct in r23953
    it "raises a FloatDomainError if other is NaN" do
      -> { @bignum.divmod(nan_value) }.should raise_error(FloatDomainError)
    end

    it "raises a ZeroDivisionError when the given argument is 0 and a Float" do
      -> { @bignum.divmod(0.0) }.should raise_error(ZeroDivisionError)
      -> { (-@bignum).divmod(0.0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a TypeError when the given argument is not an Integer" do
      -> { @bignum.divmod(mock('10')) }.should raise_error(TypeError)
      -> { @bignum.divmod("10") }.should raise_error(TypeError)
      -> { @bignum.divmod(:symbol) }.should raise_error(TypeError)
    end
  end
end
