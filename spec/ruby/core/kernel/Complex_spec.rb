require_relative '../../spec_helper'

describe "Kernel.Complex()" do
  describe "when passed [Complex, Complex]" do
    it "returns a new Complex number based on the two given numbers" do
      Complex(Complex(3, 4), Complex(5, 6)).should == Complex(3 - 6, 4 + 5)
      Complex(Complex(1.5, 2), Complex(-5, 6.3)).should == Complex(1.5 - 6.3, 2 - 5)
    end
  end

  describe "when passed [Complex]" do
    it "returns the passed Complex number" do
      Complex(Complex(1, 2)).should == Complex(1, 2)
      Complex(Complex(-3.4, bignum_value)).should == Complex(-3.4, bignum_value)
    end
  end

  describe "when passed [Integer, Integer]" do
    it "returns a new Complex number" do
      Complex(1, 2).should be_an_instance_of(Complex)
      Complex(1, 2).real.should == 1
      Complex(1, 2).imag.should == 2

      Complex(-3, -5).should be_an_instance_of(Complex)
      Complex(-3, -5).real.should == -3
      Complex(-3, -5).imag.should == -5

      Complex(3.5, -4.5).should be_an_instance_of(Complex)
      Complex(3.5, -4.5).real.should == 3.5
      Complex(3.5, -4.5).imag.should == -4.5

      Complex(bignum_value, 30).should be_an_instance_of(Complex)
      Complex(bignum_value, 30).real.should == bignum_value
      Complex(bignum_value, 30).imag.should == 30
    end
  end

  describe "when passed [Integer/Float]" do
    it "returns a new Complex number with 0 as the imaginary component" do
      # Guard against the Mathn library
      guard -> { !defined?(Math.rsqrt) } do
        Complex(1).should be_an_instance_of(Complex)
        Complex(1).imag.should == 0
        Complex(1).real.should == 1

        Complex(-3).should be_an_instance_of(Complex)
        Complex(-3).imag.should == 0
        Complex(-3).real.should == -3

        Complex(-4.5).should be_an_instance_of(Complex)
        Complex(-4.5).imag.should == 0
        Complex(-4.5).real.should == -4.5

        Complex(bignum_value).should be_an_instance_of(Complex)
        Complex(bignum_value).imag.should == 0
        Complex(bignum_value).real.should == bignum_value
      end
    end
  end

  describe "when passed a String" do
    it "needs to be reviewed for spec completeness"
  end

  describe "when passed an Object which responds to #to_c" do
    it "returns the passed argument" do
      obj = Object.new; def obj.to_c; 1i end
      Complex(obj).should == Complex(0, 1)
    end
  end

  describe "when passed a Numeric which responds to #real? with false" do
    it "returns the passed argument" do
      n = mock_numeric("unreal")
      n.should_receive(:real?).any_number_of_times.and_return(false)
      Complex(n).should equal(n)
    end
  end

  describe "when passed a Numeric which responds to #real? with true" do
    it "returns a Complex with the passed argument as the real component and 0 as the imaginary component" do
      n = mock_numeric("real")
      n.should_receive(:real?).any_number_of_times.and_return(true)
      result = Complex(n)
      result.real.should equal(n)
      result.imag.should equal(0)
    end
  end

  describe "when passed Numerics n1 and n2 and at least one responds to #real? with false" do
    [[false, false], [false, true], [true, false]].each do |r1, r2|
      it "returns n1 + n2 * Complex(0, 1)" do
        n1 = mock_numeric("n1")
        n2 = mock_numeric("n2")
        n3 = mock_numeric("n3")
        n4 = mock_numeric("n4")
        n1.should_receive(:real?).any_number_of_times.and_return(r1)
        n2.should_receive(:real?).any_number_of_times.and_return(r2)
        n2.should_receive(:*).with(Complex(0, 1)).and_return(n3)
        n1.should_receive(:+).with(n3).and_return(n4)
        Complex(n1, n2).should equal(n4)
      end
    end
  end

  describe "when passed two Numerics and both respond to #real? with true" do
    it "returns a Complex with the passed arguments as real and imaginary components respectively" do
      n1 = mock_numeric("n1")
      n2 = mock_numeric("n2")
      n1.should_receive(:real?).any_number_of_times.and_return(true)
      n2.should_receive(:real?).any_number_of_times.and_return(true)
      result = Complex(n1, n2)
      result.real.should equal(n1)
      result.imag.should equal(n2)
    end
  end

  describe "when passed a single non-Numeric" do
    it "coerces the passed argument using #to_c" do
      n = mock("n")
      c = Complex(0, 0)
      n.should_receive(:to_c).and_return(c)
      Complex(n).should equal(c)
    end
  end

  describe "when passed a non-Numeric second argument" do
    it "raises TypeError" do
      lambda { Complex(:sym, :sym) }.should raise_error(TypeError)
      lambda { Complex(0,    :sym) }.should raise_error(TypeError)
    end
  end

  describe "when passed nil" do
    it "raises TypeError" do
      lambda { Complex(nil) }.should raise_error(TypeError, "can't convert nil into Complex")
      lambda { Complex(0, nil) }.should raise_error(TypeError, "can't convert nil into Complex")
      lambda { Complex(nil, 0) }.should raise_error(TypeError, "can't convert nil into Complex")
    end
  end

  ruby_version_is "2.6" do
    describe "when passed exception: false" do
      describe "and [Numeric]" do
        it "returns a complex number" do
          Complex("123", exception: false).should == Complex(123)
        end
      end

      describe "and [non-Numeric]" do
        it "swallows an error" do
          Complex(:sym, exception: false).should == nil
        end
      end

      describe "and [non-Numeric, Numeric] argument" do
        it "throws a TypeError" do
          lambda { Complex(:sym, 0, exception: false) }.should raise_error(TypeError, "not a real")
        end
      end

      describe "and [anything, non-Numeric] argument" do
        it "swallows an error" do
          Complex("a",  :sym, exception: false).should == nil
          Complex(:sym, :sym, exception: false).should == nil
          Complex(0,    :sym, exception: false).should == nil
        end
      end

      describe "and non-numeric String arguments" do
        it "swallows an error" do
          Complex("a", "b", exception: false).should == nil
          Complex("a", 0, exception: false).should == nil
          Complex(0, "b", exception: false).should == nil
        end
      end

      describe "and nil arguments" do
        it "swallows an error" do
          Complex(nil, exception: false).should == nil
          Complex(0, nil, exception: false).should == nil
          Complex(nil, 0, exception: false).should == nil
        end
      end
    end
  end
end
