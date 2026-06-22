require_relative '../../spec_helper'

describe "SizedQueue#enq" do
  it "is an alias of SizedQueue#<<" do
    SizedQueue.instance_method(:enq).should == SizedQueue.instance_method(:<<)
  end
end
