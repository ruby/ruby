require_relative '../../spec_helper'

describe "Float#to_f" do
  it "returns self" do
    -500.3.to_f.should == -500.3
    267.51.to_f.should == 267.51
    1.1412.to_f.should == 1.1412
  end
end
