require_relative '../../spec_helper'

describe "Kernel#not_nil!" do
  it "returns self" do
    42.not_nil!.should == 42
  end
end

describe "Kernel#not_nil" do
  it "returns self" do
    42.not_nil { "not 42" }.should == 42
  end
end
