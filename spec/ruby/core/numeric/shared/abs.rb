require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :numeric_abs, shared: true do
  before :each do
    @obj = NumericSpecs::Subclass.new
  end

  it "returns self when self is greater than 0" do
    @obj.should_receive(:<).with(0).and_return(false)
    @obj.send(@method).should == @obj
  end

  it "returns self\#@- when self is less than 0" do
    @obj.should_receive(:<).with(0).and_return(true)
    @obj.should_receive(:-@).and_return(:absolute_value)
    @obj.send(@method).should == :absolute_value
  end
end
