require_relative '../../spec_helper'
require_relative '../numeric/fixtures/classes'

describe "Complex#inspect" do
  it "returns (${real}+${image}i) for positive imaginary parts" do
    Complex(1).inspect.should == "(1+0i)"
    Complex(7).inspect.should == "(7+0i)"
    Complex(-1, 4).inspect.should == "(-1+4i)"
    Complex(-7, 6.7).inspect.should == "(-7+6.7i)"
  end

  it "returns (${real}-${image}i) for negative imaginary parts" do
    Complex(0, -1).inspect.should == "(0-1i)"
    Complex(-1, -4).inspect.should == "(-1-4i)"
    Complex(-7, -6.7).inspect.should == "(-7-6.7i)"
  end

  it "calls #inspect on real and imaginary" do
    real = NumericSpecs::Subclass.new
    # + because of https://bugs.ruby-lang.org/issues/20337
    real.should_receive(:inspect).and_return(+"1")
    imaginary = NumericSpecs::Subclass.new
    imaginary.should_receive(:inspect).and_return("2")
    imaginary.should_receive(:<).any_number_of_times.and_return(false)
    Complex(real, imaginary).inspect.should == "(1+2i)"
  end

  it "adds an `*' before the `i' if the last character of the imaginary part is not numeric" do
    real = NumericSpecs::Subclass.new
    # + because of https://bugs.ruby-lang.org/issues/20337
    real.should_receive(:inspect).and_return(+"(1)")
    imaginary = NumericSpecs::Subclass.new
    imaginary.should_receive(:inspect).and_return("(2)")
    imaginary.should_receive(:<).any_number_of_times.and_return(false)
    Complex(real, imaginary).inspect.should == "((1)+(2)*i)"
  end
end
