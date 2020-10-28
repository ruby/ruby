require_relative '../../spec_helper'

describe "Numeric#infinite?" do
  it "returns nil by default" do
    o = mock_numeric("infinite")
    o.infinite?.should == nil
  end
end
