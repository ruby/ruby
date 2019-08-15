require_relative '../../spec_helper'

describe "Float#zero?" do
  it "returns true if self is 0.0" do
    0.0.zero?.should == true
    1.0.zero?.should == false
    -1.0.zero?.should == false
  end
end
