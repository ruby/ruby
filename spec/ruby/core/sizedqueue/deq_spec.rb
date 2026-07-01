require_relative '../../spec_helper'

describe "SizedQueue#deq" do
  it "is an alias of SizedQueue#pop" do
    SizedQueue.instance_method(:deq).should == SizedQueue.instance_method(:pop)
  end
end
