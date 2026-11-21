require_relative '../../spec_helper'

describe "SizedQueue#shift" do
  it "is an alias of SizedQueue#pop" do
    SizedQueue.instance_method(:shift).should == SizedQueue.instance_method(:pop)
  end
end
