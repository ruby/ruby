require_relative '../../spec_helper'

describe "TrueClass#true?" do
  it "returns true" do
    true.true?.should == true
  end
end
