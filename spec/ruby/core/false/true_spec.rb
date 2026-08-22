require_relative '../../spec_helper'

describe "FalseClass#true?" do
  it "returns false" do
    false.true?.should == false
  end
end
