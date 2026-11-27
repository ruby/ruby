require_relative '../../spec_helper'

describe "Complex#rectangular" do
  before :each do
    @numbers = [
      Complex(1),
      Complex(0, 20),
      Complex(0, 0),
      Complex(0.0),
      Complex(9999999**99),
      Complex(-20),
      Complex.polar(76, 10)
    ]
  end

  it "returns an Array" do
    @numbers.each do |number|
      number.rectangular.should.instance_of?(Array)
    end
  end

  it "returns a two-element Array" do
    @numbers.each do |number|
      number.rectangular.size.should == 2
    end
  end

  it "returns the real part of self as the first element" do
    @numbers.each do |number|
      number.rectangular.first.should == number.real
    end
  end

  it "returns the imaginary part of self as the last element" do
    @numbers.each do |number|
      number.rectangular.last.should == number.imaginary
    end
  end

  it "raises an ArgumentError if given any arguments" do
    @numbers.each do |number|
      -> { number.rectangular(number) }.should.raise(ArgumentError)
    end
  end
end

describe "Complex.rectangular" do
  describe "passed a Numeric n which responds to #real? with true" do
    it "returns a Complex with real part n and imaginary part 0" do
      n = mock_numeric('n')
      n.should_receive(:real?).any_number_of_times.and_return(true)
      result = Complex.rectangular(n)
      result.real.should == n
      result.imag.should == 0
    end
  end

  describe "passed a Numeric which responds to #real? with false" do
    it "raises TypeError" do
      n = mock_numeric('n')
      n.should_receive(:real?).any_number_of_times.and_return(false)
      -> { Complex.rectangular(n) }.should.raise(TypeError)
    end
  end

  describe "passed Numerics n1 and n2 and at least one responds to #real? with false" do
    [[false, false], [false, true], [true, false]].each do |r1, r2|
      it "raises TypeError" do
        n1 = mock_numeric('n1')
        n2 = mock_numeric('n2')
        n1.should_receive(:real?).any_number_of_times.and_return(r1)
        n2.should_receive(:real?).any_number_of_times.and_return(r2)
        -> { Complex.rectangular(n1, n2) }.should.raise(TypeError)
      end
    end
  end

  describe "passed Numerics n1 and n2 and both respond to #real? with true" do
    it "returns a Complex with real part n1 and imaginary part n2" do
      n1 = mock_numeric('n1')
      n2 = mock_numeric('n2')
      n1.should_receive(:real?).any_number_of_times.and_return(true)
      n2.should_receive(:real?).any_number_of_times.and_return(true)
      result = Complex.rectangular(n1, n2)
      result.real.should == n1
      result.imag.should == n2
    end
  end

  describe "when passed a Complex" do
    it "raises a TypeError when the imaginary part is not zero" do
      -> {
        Complex.rectangular(1.0+1i, 2)
      }.should.raise(TypeError)

      -> {
        Complex.rectangular(1.0, 2i)
      }.should.raise(TypeError)
    end

    it "ignores the imaginary part if it is zero" do
      result = Complex.rectangular(1.0+0i, 2+0.0i)
      result.real.should == 1.0
      result.imag.should == 2
    end
  end

  describe "passed a non-Numeric" do
    it "raises TypeError" do
      -> { Complex.rectangular(:sym) }.should.raise(TypeError)
      -> { Complex.rectangular(0, :sym) }.should.raise(TypeError)
    end
  end
end
