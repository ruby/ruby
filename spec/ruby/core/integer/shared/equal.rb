describe :integer_equal, shared: true do
  context "fixnum" do
    it "returns true if self has the same value as other" do
      1.send(@method, 1).should == true
      9.send(@method, 5).should == false

      # Actually, these call Float#==, Bignum#== etc.
      9.send(@method, 9.0).should == true
      9.send(@method, 9.01).should == false

      10.send(@method, bignum_value).should == false
    end

    it "calls 'other == self' if the given argument is not a Integer" do
      1.send(@method, '*').should == false

      obj = mock('one other')
      obj.should_receive(:==).any_number_of_times.and_return(false)
      1.send(@method, obj).should == false

      obj = mock('another')
      obj.should_receive(:==).any_number_of_times.and_return(true)
      2.send(@method, obj).should == true
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value
    end

    it "returns true if self has the same value as the given argument" do
      @bignum.send(@method, @bignum).should == true
      @bignum.send(@method, @bignum.to_f).should == true

      @bignum.send(@method, @bignum + 1).should == false
      (@bignum + 1).send(@method, @bignum).should == false

      @bignum.send(@method, 9).should == false
      @bignum.send(@method, 9.01).should == false

      @bignum.send(@method, bignum_value(10)).should == false
    end

    it "calls 'other == self' if the given argument is not an Integer" do
      obj = mock('not integer')
      obj.should_receive(:==).and_return(true)
      @bignum.send(@method, obj).should == true
    end

    it "returns the result of 'other == self' as a boolean" do
      obj = mock('not integer')
      obj.should_receive(:==).exactly(2).times.and_return("woot", nil)
      @bignum.send(@method, obj).should == true
      @bignum.send(@method, obj).should == false
    end
  end
end
