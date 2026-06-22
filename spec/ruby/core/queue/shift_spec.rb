require_relative '../../spec_helper'

describe "Queue#shift" do
  it "is an alias of Queue#pop" do
    Queue.instance_method(:shift).should == Queue.instance_method(:pop)
  end
end
