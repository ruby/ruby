require_relative '../../spec_helper'

describe "Data" do
  it "is a new constant" do
    Data.superclass.should == Object
  end

  it "is not deprecated" do
    -> { Data }.should_not complain
  end
end
