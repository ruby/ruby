require_relative '../../spec_helper'

describe "Integer#%" do
  context "fixnum" do
    it "returns the modulus obtained from dividing self by the given argument" do
      # test all possible combinations:
      # - integer/double/bignum argument
      # - positive/negative argument
      # - positive/negative self
      # - self greater/smaller than argument

      (13 % 4).should == 1
      (4 % 13).should == 4

      (13 % 4.0).should == 1
      (4 % 13.0).should == 4

      (-200 % 256).should == 56
      (-1000 % 512).should == 24

      (-200 % -256).should == -200
      (-1000 % -512).should == -488

      (200 % -256).should == -56
      (1000 % -512).should == -24

      (13 % -4.0).should == -3.0
      (4 % -13.0).should == -9.0

      (-13 % -4.0).should == -1.0
      (-4 % -13.0).should == -4.0

      (-13 % 4.0).should == 3.0
      (-4 % 13.0).should == 9.0

      (1 % 2.0).should == 1.0
      (200 % bignum_value).should == 200

      (4 % bignum_value(10)).should == 4
      (4 % -bignum_value(10)).should == -18446744073709551622
      (-4 % bignum_value(10)).should == 18446744073709551622
      (-4 % -bignum_value(10)).should == -4
    end

    it "raises a ZeroDivisionError when the given argument is 0" do
      -> { 13 % 0  }.should.raise(ZeroDivisionError)
      -> { 0 % 0   }.should.raise(ZeroDivisionError)
      -> { -10 % 0 }.should.raise(ZeroDivisionError)
    end

    it "raises a ZeroDivisionError when the given argument is 0 and a Float" do
      -> { 0 % 0.0 }.should.raise(ZeroDivisionError)
      -> { 10 % 0.0 }.should.raise(ZeroDivisionError)
      -> { -10 % 0.0 }.should.raise(ZeroDivisionError)
    end

    it "raises a TypeError when given a non-Integer" do
      -> {
        (obj = mock('10')).should_receive(:to_int).any_number_of_times.and_return(10)
        13 % obj
      }.should.raise(TypeError)
      -> { 13 % "10"    }.should.raise(TypeError)
      -> { 13 % :symbol }.should.raise(TypeError)
    end
  end

  context "bignum" do
    before :each do
      @bignum = bignum_value(10)
    end

    it "returns the modulus obtained from dividing self by the given argument" do
      # test all possible combinations:
      # - integer/double/bignum argument
      # - positive/negative argument
      # - positive/negative self
      # - self greater/smaller than argument

      (@bignum % 5).should == 1
      (@bignum % -5).should == -4
      (-@bignum % 5).should == 4
      (-@bignum % -5).should == -1

      (@bignum % 2.22).should be_close(1.5603603603605034, TOLERANCE)
      (@bignum % -2.22).should be_close(-0.6596396396394968, TOLERANCE)
      (-@bignum % 2.22).should be_close(0.6596396396394968, TOLERANCE)
      (-@bignum % -2.22).should be_close(-1.5603603603605034, TOLERANCE)

      (@bignum % (@bignum + 10)).should == 18446744073709551626
      (@bignum % -(@bignum + 10)).should == -10
      (-@bignum % (@bignum + 10)).should == 10
      (-@bignum % -(@bignum + 10)).should == -18446744073709551626

      ((@bignum + 10) % @bignum).should == 10
      ((@bignum + 10) % -@bignum).should == -18446744073709551616
      (-(@bignum + 10) % @bignum).should == 18446744073709551616
      (-(@bignum + 10) % -@bignum).should == -10
    end

    it "raises a ZeroDivisionError when the given argument is 0" do
      -> { @bignum % 0 }.should.raise(ZeroDivisionError)
      -> { -@bignum % 0 }.should.raise(ZeroDivisionError)
    end

    it "raises a ZeroDivisionError when the given argument is 0 and a Float" do
      -> { @bignum % 0.0 }.should.raise(ZeroDivisionError)
      -> { -@bignum % 0.0 }.should.raise(ZeroDivisionError)
    end

    it "raises a TypeError when given a non-Integer" do
      -> { @bignum % mock('10') }.should.raise(TypeError)
      -> { @bignum % "10" }.should.raise(TypeError)
      -> { @bignum % :symbol }.should.raise(TypeError)
    end
  end
end

describe "Integer#modulo" do
  it "is an alias of Integer#%" do
    Integer.instance_method(:modulo).should == Integer.instance_method(:%)
  end
end
