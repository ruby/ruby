require_relative '../../spec_helper'

describe "Queue#enq" do
  it "is an alias of Queue#<<" do
    Queue.instance_method(:enq).should == Queue.instance_method(:<<)
  end
end
