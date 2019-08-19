require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Numeric#nonzero?" do
  before :each do
    @obj = NumericSpecs::Subclass.new
  end

  it "returns self if self#zero? is false" do
    @obj.should_receive(:zero?).and_return(false)
    @obj.nonzero?.should == @obj
  end

  it "returns nil if self#zero? is true" do
    @obj.should_receive(:zero?).and_return(true)
    @obj.nonzero?.should == nil
  end
end
