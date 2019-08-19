require_relative '../../spec_helper'

require 'bigdecimal'

describe "Integer#coerce" do
  context "fixnum" do
    describe "when given a Fixnum" do
      it "returns an array containing two Fixnums" do
        1.coerce(2).should == [2, 1]
        1.coerce(2).map { |i| i.class }.should == [Fixnum, Fixnum]
      end
    end

    describe "when given a String" do
      it "raises an ArgumentError when trying to coerce with a non-number String" do
        -> { 1.coerce(":)") }.should raise_error(ArgumentError)
      end

      it "returns  an array containing two Floats" do
        1.coerce("2").should == [2.0, 1.0]
        1.coerce("-2").should == [-2.0, 1.0]
      end
    end

    it "raises a TypeError when trying to coerce with nil" do
      -> { 1.coerce(nil) }.should raise_error(TypeError)
    end

    it "tries to convert the given Object into a Float by using #to_f" do
      (obj = mock('1.0')).should_receive(:to_f).and_return(1.0)
      2.coerce(obj).should == [1.0, 2.0]

      (obj = mock('0')).should_receive(:to_f).and_return('0')
      -> { 2.coerce(obj).should == [1.0, 2.0] }.should raise_error(TypeError)
    end

    it "raises a TypeError when given an Object that does not respond to #to_f" do
      -> { 1.coerce(mock('x'))  }.should raise_error(TypeError)
      -> { 1.coerce(1..4)       }.should raise_error(TypeError)
      -> { 1.coerce(:test)      }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    it "coerces other to a Bignum and returns [other, self] when passed a Fixnum" do
      a = bignum_value
      ary = a.coerce(2)

      ary[0].should be_kind_of(Bignum)
      ary[1].should be_kind_of(Bignum)
      ary.should == [2, a]
    end

    it "returns [other, self] when passed a Bignum" do
      a = bignum_value
      b = bignum_value
      ary = a.coerce(b)

      ary[0].should be_kind_of(Bignum)
      ary[1].should be_kind_of(Bignum)
      ary.should == [b, a]
    end

    it "raises a TypeError when not passed a Fixnum or Bignum" do
      a = bignum_value

      -> { a.coerce(nil)         }.should raise_error(TypeError)
      -> { a.coerce(mock('str')) }.should raise_error(TypeError)
      -> { a.coerce(1..4)        }.should raise_error(TypeError)
      -> { a.coerce(:test)       }.should raise_error(TypeError)
    end

    it "coerces both values to Floats and returns [other, self] when passed a Float" do
      a = bignum_value
      a.coerce(1.2).should == [1.2, a.to_f]
    end

    it "coerces both values to Floats and returns [other, self] when passed a String" do
      a = bignum_value
      a.coerce("123").should == [123.0, a.to_f]
    end

    it "calls #to_f to coerce other to a Float" do
      b = mock("bignum value")
      b.should_receive(:to_f).and_return(1.2)

      a = bignum_value
      ary = a.coerce(b)

      ary.should == [1.2, a.to_f]
    end
  end

  context "bigdecimal" do
    it "produces Floats" do
      x, y = 3.coerce(BigDecimal("3.4"))
      x.class.should == Float
      x.should == 3.4
      y.class.should == Float
      y.should == 3.0
    end
  end

end
