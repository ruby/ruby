describe :integer_modulo, shared: true do
  context "fixnum" do
    it "returns the modulus obtained from dividing self by the given argument" do
      13.send(@method, 4).should == 1
      4.send(@method, 13).should == 4

      13.send(@method, 4.0).should == 1
      4.send(@method, 13.0).should == 4

      (-200).send(@method, 256).should == 56
      (-1000).send(@method, 512).should == 24

      (-200).send(@method, -256).should == -200
      (-1000).send(@method, -512).should == -488

      (200).send(@method, -256).should == -56
      (1000).send(@method, -512).should == -24

      1.send(@method, 2.0).should == 1.0
      200.send(@method, bignum_value).should == 200
    end

    it "raises a ZeroDivisionError when the given argument is 0" do
      -> { 13.send(@method, 0)  }.should raise_error(ZeroDivisionError)
      -> { 0.send(@method, 0)   }.should raise_error(ZeroDivisionError)
      -> { -10.send(@method, 0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a ZeroDivisionError when the given argument is 0 and a Float" do
      -> { 0.send(@method, 0.0) }.should raise_error(ZeroDivisionError)
      -> { 10.send(@method, 0.0) }.should raise_error(ZeroDivisionError)
      -> { -10.send(@method, 0.0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a TypeError when given a non-Integer" do
      -> {
        (obj = mock('10')).should_receive(:to_int).any_number_of_times.and_return(10)
        13.send(@method, obj)
      }.should raise_error(TypeError)
      -> { 13.send(@method, "10")    }.should raise_error(TypeError)
      -> { 13.send(@method, :symbol) }.should raise_error(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value
    end

    it "returns the modulus obtained from dividing self by the given argument" do
      @bignum.send(@method, 5).should == 1
      @bignum.send(@method, -5).should == -4
      @bignum.send(@method, -100).should == -84
      @bignum.send(@method, 2.22).should be_close(1.5603603603605034, TOLERANCE)
      @bignum.send(@method, bignum_value(10)).should == 18446744073709551616
    end

    it "raises a ZeroDivisionError when the given argument is 0" do
      -> { @bignum.send(@method, 0) }.should raise_error(ZeroDivisionError)
      -> { (-@bignum).send(@method, 0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a ZeroDivisionError when the given argument is 0 and a Float" do
      -> { @bignum.send(@method, 0.0) }.should raise_error(ZeroDivisionError)
      -> { -@bignum.send(@method, 0.0) }.should raise_error(ZeroDivisionError)
    end

    it "raises a TypeError when given a non-Integer" do
      -> { @bignum.send(@method, mock('10')) }.should raise_error(TypeError)
      -> { @bignum.send(@method, "10") }.should raise_error(TypeError)
      -> { @bignum.send(@method, :symbol) }.should raise_error(TypeError)
    end
  end
end
