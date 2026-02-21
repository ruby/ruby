require_relative '../../spec_helper'

describe "TrueClass#false?" do
  it "returns false" do
    true.false?.should == false
  end
end
