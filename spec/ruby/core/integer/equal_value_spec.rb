require_relative '../../spec_helper'

describe "Integer#==" do
  context "fixnum" do
    it "returns true if self has the same value as other" do
      (1 == 1).should == true
      (9 == 5).should == false

      # Actually, these call Float#==, Integer#== etc.
      (9 == 9.0).should == true
      (9 == 9.01).should == false

      (10 == bignum_value).should == false
    end

    it "calls 'other == self' if the given argument is not an Integer" do
      (1 == '*').should == false

      obj = mock('one other')
      obj.should_receive(:==).any_number_of_times.and_return(false)
      (1 == obj).should == false

      obj = mock('another')
      obj.should_receive(:==).any_number_of_times.and_return(true)
      (2 == obj).should == true
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value
    end

    it "returns true if self has the same value as the given argument" do
      (@bignum == @bignum).should == true
      (@bignum == @bignum.to_f).should == true

      (@bignum == @bignum + 1).should == false
      ((@bignum + 1) == @bignum).should == false

      (@bignum == 9).should == false
      (@bignum == 9.01).should == false

      (@bignum == bignum_value(10)).should == false
    end

    it "calls 'other == self' if the given argument is not an Integer" do
      obj = mock('not integer')
      obj.should_receive(:==).and_return(true)
      (@bignum == obj).should == true
    end

    it "returns the result of 'other == self' as a boolean" do
      obj = mock('not integer')
      obj.should_receive(:==).exactly(2).times.and_return("woot", nil)
      (@bignum == obj).should == true
      (@bignum == obj).should == false
    end

    it "does not lose precision when comparing with a Float" do
      ((bignum_value(1) == bignum_value.to_f)).should == false
      ((bignum_value == bignum_value.to_f)).should == true
    end
  end
end
