require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Numeric#+@" do
  it "returns self" do
    obj = NumericSpecs::Subclass.new
    obj.send(:+@).should == obj
  end
end
