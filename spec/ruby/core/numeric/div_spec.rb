require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Numeric#div" do
  before :each do
    @obj = NumericSpecs::Subclass.new
  end

  it "calls self#/ with other, then returns the #floor'ed result" do
    result = mock("Numeric#div result")
    result.should_receive(:floor).and_return(12)
    @obj.should_receive(:/).with(10).and_return(result)

    @obj.div(10).should == 12
  end

  it "raises ZeroDivisionError for 0" do
    -> { @obj.div(0) }.should raise_error(ZeroDivisionError)
    -> { @obj.div(0.0) }.should raise_error(ZeroDivisionError)
    -> { @obj.div(Complex(0,0)) }.should raise_error(ZeroDivisionError)
  end
end
