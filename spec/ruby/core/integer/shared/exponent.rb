describe :integer_exponent, shared: true do
  context "fixnum" do
    it "returns self raised to the given power" do
      2.send(@method, 0).should eql 1
      2.send(@method, 1).should eql 2
      2.send(@method, 2).should eql 4

      9.send(@method, 0.5).should eql 3.0
      9.send(@method, Rational(1, 2)).should eql 3.0
      5.send(@method, -1).to_f.to_s.should == '0.2'

      2.send(@method, 40).should eql 1099511627776
    end

    it "overflows the answer to a bignum transparently" do
      2.send(@method, 29).should eql 536870912
      2.send(@method, 30).should eql 1073741824
      2.send(@method, 31).should eql 2147483648
      2.send(@method, 32).should eql 4294967296

      2.send(@method, 61).should eql 2305843009213693952
      2.send(@method, 62).should eql 4611686018427387904
      2.send(@method, 63).should eql 9223372036854775808
      2.send(@method, 64).should eql 18446744073709551616
      8.send(@method, 23).should eql 590295810358705651712
    end

    it "raises negative numbers to the given power" do
      (-2).send(@method, 29).should eql(-536870912)
      (-2).send(@method, 30).should eql(1073741824)
      (-2).send(@method, 31).should eql(-2147483648)
      (-2).send(@method, 32).should eql(4294967296)

      (-2).send(@method, 61).should eql(-2305843009213693952)
      (-2).send(@method, 62).should eql(4611686018427387904)
      (-2).send(@method, 63).should eql(-9223372036854775808)
      (-2).send(@method, 64).should eql(18446744073709551616)
    end

    it "can raise 1 to a bignum safely" do
      1.send(@method, 4611686018427387904).should eql 1
    end

    it "can raise -1 to a bignum safely" do
      (-1).send(@method, 4611686018427387904).should eql(1)
      (-1).send(@method, 4611686018427387905).should eql(-1)
    end

    it "returns Float::INFINITY when the number is too big" do
      -> {
        2.send(@method, 427387904).should == Float::INFINITY
      }.should complain(/warning: in a\*\*b, b may be too big/)
    end

    it "raises a ZeroDivisionError for 0 ** -1" do
      -> { 0.send(@method, -1) }.should raise_error(ZeroDivisionError)
      -> { 0.send(@method, Rational(-1, 1)) }.should raise_error(ZeroDivisionError)
    end

    it "returns Float::INFINITY for 0 ** -1.0" do
      0.send(@method, -1.0).should == Float::INFINITY
    end

    it "raises a TypeError when given a non-numeric power" do
      -> { 13.send(@method, "10") }.should raise_error(TypeError)
      -> { 13.send(@method, :symbol) }.should raise_error(TypeError)
      -> { 13.send(@method, nil) }.should raise_error(TypeError)
    end

    it "coerces power and calls #**" do
      num_2 = mock("2")
      num_13 = mock("13")
      num_2.should_receive(:coerce).with(13).and_return([num_13, num_2])
      num_13.should_receive(:**).with(num_2).and_return(169)

      13.send(@method, num_2).should == 169
    end

    it "returns Float when power is Float" do
      2.send(@method, 2.0).should == 4.0
    end

    it "returns Rational when power is Rational" do
      2.send(@method, Rational(2, 1)).should == Rational(4, 1)
    end

    it "returns a complex number when negative and raised to a fractional power" do
      (-8).send(@method, 1.0/3)         .should be_close(Complex(1, 1.73205), TOLERANCE)
      (-8).send(@method, Rational(1, 3)).should be_close(Complex(1, 1.73205), TOLERANCE)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(47)
    end

    it "returns self raised to other power" do
      (@bignum.send(@method, 4)).should == 7237005577332262361485077344629993318496048279512298547155833600056910050625
      (@bignum.send(@method, 1.2)).should be_close(57262152889751597425762.57804, TOLERANCE)
    end

    it "raises a TypeError when given a non-Integer" do
      -> { @bignum.send(@method, mock('10')) }.should raise_error(TypeError)
      -> { @bignum.send(@method, "10") }.should raise_error(TypeError)
      -> { @bignum.send(@method, :symbol) }.should raise_error(TypeError)
    end

    it "switch to a Float when the values is too big" do
      flt = nil
      -> {
        flt = @bignum.send(@method, @bignum)
      }.should complain(/warning: in a\*\*b, b may be too big/)
      flt.should be_kind_of(Float)
      flt.infinite?.should == 1
    end

    it "returns a complex number when negative and raised to a fractional power" do
      ((-@bignum).send(@method, (1.0/3)))      .should be_close(Complex(1048576,1816186.907597341), TOLERANCE)
      ((-@bignum).send(@method, Rational(1,3))).should be_close(Complex(1048576,1816186.907597341), TOLERANCE)
    end
  end
end
