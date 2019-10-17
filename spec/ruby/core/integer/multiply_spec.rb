require_relative '../../spec_helper'
require_relative 'shared/arithmetic_coerce'

describe "Integer#*" do
  ruby_version_is "2.4"..."2.5" do
    it_behaves_like :integer_arithmetic_coerce_rescue, :*
  end

  ruby_version_is "2.5" do
    it_behaves_like :integer_arithmetic_coerce_not_rescue, :*
  end

  context "fixnum" do
    it "returns self multiplied by the given Integer" do
      (4923 * 2).should == 9846
      (1342177 * 800).should == 1073741600
      (65536 * 65536).should == 4294967296

      (256 * bignum_value).should == 2361183241434822606848
      (6712 * 0.25).should == 1678.0
    end

    it "raises a TypeError when given a non-Integer" do
      -> {
        (obj = mock('10')).should_receive(:to_int).any_number_of_times.and_return(10)
        13 * obj
      }.should raise_error(TypeError)
      -> { 13 * "10"    }.should raise_error(TypeError)
      -> { 13 * :symbol }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(772)
    end

    it "returns self multiplied by the given Integer" do
      (@bignum * (1/bignum_value(0xffff).to_f)).should be_close(1.0, TOLERANCE)
      (@bignum * (1/bignum_value(0xffff).to_f)).should be_close(1.0, TOLERANCE)
      (@bignum * 10).should == 92233720368547765800
      (@bignum * (@bignum - 40)).should == 85070591730234629737795195287525433200
    end

    it "raises a TypeError when given a non-Integer" do
      -> { @bignum * mock('10') }.should raise_error(TypeError)
      -> { @bignum * "10" }.should raise_error(TypeError)
      -> { @bignum * :symbol }.should raise_error(TypeError)
    end
  end
end
