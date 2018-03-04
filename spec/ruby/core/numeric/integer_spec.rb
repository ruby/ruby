require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Numeric#integer?" do
  it "returns false" do
    NumericSpecs::Subclass.new.integer?.should == false
  end
end
