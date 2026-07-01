require_relative '../../spec_helper'

describe "Queue#deq" do
  it "is an alias of Queue#pop" do
    Queue.instance_method(:deq).should == Queue.instance_method(:pop)
  end
end
