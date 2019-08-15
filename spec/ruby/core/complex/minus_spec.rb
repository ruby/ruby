require_relative '../../spec_helper'

describe "Complex#-" do
  describe "with Complex" do
    it "subtracts both the real and imaginary components" do
      (Complex(1, 2) - Complex(10, 20)).should == Complex(1 - 10, 2 - 20)
      (Complex(1.5, 2.1) - Complex(100.2, -30.3)).should == Complex(1.5 - 100.2, 2.1 - (-30.3))
    end
  end

  describe "with Integer" do
    it "subtracts the real number from the real component of self" do
      (Complex(1, 2) - 50).should == Complex(-49, 2)
      (Complex(1, 2) - 50.5).should == Complex(-49.5, 2)
    end
  end

  describe "with Object" do
    it "tries to coerce self into other" do
      value = Complex(3, 9)

      obj = mock("Object")
      obj.should_receive(:coerce).with(value).and_return([2, 5])
      (value - obj).should == 2 - 5
    end
  end

  describe "passed Numeric which responds to #real? with true" do
    it "coerces the passed argument to the type of the real part and subtracts the resulting elements" do
      n = mock_numeric('n')
      n.should_receive(:real?).and_return(true)
      n.should_receive(:coerce).with(1).and_return([1, 4])
      (Complex(1, 2) - n).should == Complex(-3, 2)
    end
  end

  describe "passed Numeric which responds to #real? with false" do
    it "coerces the passed argument to Complex and subtracts the resulting elements" do
      n = mock_numeric('n')
      n.should_receive(:real?).and_return(false)
      n.should_receive(:coerce).with(Complex(1, 2)).and_return([Complex(1, 2), Complex(3, 4)])
      (Complex(1, 2) - n).should == Complex(-2, -2)
    end
  end
end
